'use strict';
'require baseclass';
'require form';
'require rpc';
'require ui';
'require uci';

// Credentials travel only in the existing authenticated write RPC body,
// never sessionStorage, URLs or notifications.
// A successful NFC RPC submission authorizes the write; wireless apply is
// deliberately unchecked because changing the password can disconnect LuCI.
// Partition intent by login session; never replay another user's browser intent.
const storageKey = 'xinfc-wireless-sync-v1-' + L.env.sessionid;
const fields = ['ssid', 'key', 'encryption'];
const pending = new Map();
let sequence = 0;
let selecting = false;
let expires = 0;

const callAccess = rpc.declare({
	object: 'session', method: 'access',
	params: ['scope', 'object', 'function'], expect: { access: false }
});
const callStatus = rpc.declare({
	object: 'luci.xinfc', method: 'status', expect: { '': {} }
});
const callWrite = rpc.declare({
	object: 'luci.xinfc', method: 'write',
	params: ['section', 'ssid', 'password', 'encryption'], expect: { '': {} }, nobatch: true
});

function remember() {
	try {
		if (pending.size)
			sessionStorage.setItem(storageKey, JSON.stringify({
				sections: Array.from(pending.keys()), expires: expires
			}));
		else
			sessionStorage.removeItem(storageKey);
	}
	catch (e) { /* Private browsing may disable storage; in-page intent still works. */ }
}

try {
	const saved = JSON.parse(sessionStorage.getItem(storageKey) || 'null');
	if (saved && saved.expires > Date.now() && Array.isArray(saved.sections)) {
		expires = saved.expires;
		saved.sections.filter(id => typeof id === 'string' && /^[a-zA-Z0-9_]{1,64}$/.test(id))
			.forEach(id => pending.set(id, ++sequence));
	}
	else
		sessionStorage.removeItem(storageKey);
}
catch (e) { /* A malformed or unavailable cache never authorizes a write. */ }

function credentials(section) {
	return fields.map(field => uci.get('wireless', section, field) || '');
}

function eligible(section) {
	const iface = uci.get('wireless', section);
	return iface && iface['.type'] === 'wifi-iface' && iface.mode === 'ap' &&
		iface.disabled !== '1' && uci.get('wireless', iface.device, 'disabled') !== '1' &&
		iface.ppsk !== '1' &&
		['psk2', 'psk2+ccmp', 'psk2+aes', 'sae-mixed'].includes(iface.encryption);
}

function notify(message, type) {
	ui.addNotification(null, E('p', {}, [message]), type || 'info');
}

const originalApply = ui.changes.apply;
ui.changes.apply = function() {
	const context = this, args = arguments;
	if (selecting)
		return Promise.resolve();
	if (expires <= Date.now()) {
		pending.clear();
		remember();
	}
	if (!pending.size)
		return originalApply.apply(context, args);
	selecting = true;
	return uci.changes().then(changes => {
		const edits = changes.wireless || [];
		const candidates = Array.from(pending.keys()).filter(id => eligible(id) && edits.some(edit =>
			edit[1] === id && (fields.includes(edit[2]) || edit[0] === 'add')));
		const order = new Map(pending);
		// Expired/reverted/deleted/unsupported interfaces cannot cause later writes.
		pending.clear();
		remember();
		if (!candidates.length) {
			originalApply.apply(context, args);
			return;
		}
		// One NFC tag can hold one network. Use the interface most recently
		// edited by the user; do not ask about or overwrite the other band.
		const section = candidates.sort((a, b) =>
			(order.get(b) || 0) - (order.get(a) || 0))[0];
		const [ssid, password, encryption] = credentials(section);
		return callWrite('', ssid, password, encryption).then(result => {
			if (result.ok)
				notify(_('已提交当前修改频段的 NFC 同步任务，请到“服务 → AX3000T NFC”确认读回校验结果。'));
			else
				notify(_('NFC 后台拒绝了同步请求，仍将应用当前无线配置；请到“服务 → AX3000T NFC”检查。'), 'warning');
		}, error => {
			notify(_('NFC 同步请求失败，仍将应用当前无线配置；请到“服务 → AX3000T NFC”检查。') +
				(error && error.message ? ' ' + error.message : ''), 'warning');
		}).then(() => {
			// A wireless password change commonly disconnects this browser.
			// Do not start LuCI's 90-second checked-apply rollback in that case.
			originalApply.call(context, false);
		});
	}, () => {
		notify(_('无法核对待应用的无线变更，本次不自动写入 NFC；请在 NFC 页面检查。'), 'warning');
		return originalApply.apply(context, args);
	}).finally(() => { selecting = false; });
};

document.addEventListener('uci-reverted', function() {
	pending.clear();
	remember();
});

return baseclass.extend({
	addOption: function(section) {
		if (!L.hasViewPermission())
			return Promise.resolve();
		return Promise.all([
			callAccess('ubus', 'luci.xinfc', 'write'), callStatus()
		]).then(results => {
			const status = results[1];
			if (!results[0] || !status.ok || !status.supported || !status.writer_available)
				return;
			const id = section.section;
			const before = credentials(id);
			const option = section.taboption('encryption', form.Flag, '_xinfc_sync',
				_('同时更改 NFC'),
				_('默认勾选。提交本接口的“保存并应用”时，先将当前连接信息提交到 NFC，再应用无线配置；仅保存或取消不写入。本次无线应用不自动回滚，请确认密码正确并准备有线管理。NFC 可被近距离读取。支持 WPA2-AES／WPA2-WPA3 混合、SSID 2–28 字节、密码 8–63 字节。'));
			option.default = option.enabled;
			option.rmempty = false;
			option.depends('mode', 'ap');
			option.depends('mode', 'ap-wds');
			option.cfgvalue = function() { return this.enabled; };
			// This is a one-shot UI instruction, not a hostapd/UCI setting.
			option.write = option.remove = function() {};
			const map = section.map, save = map.save;
			map.save = function() {
				const selected = option.isActive(id) && option.formvalue(id) === option.enabled;
				return save.apply(this, arguments).then(value => {
					const after = credentials(id);
					if (!selected || !eligible(id))
						pending.delete(id);
					else if (after.some((entry, index) => entry !== before[index])) {
						pending.delete(id);
						pending.set(id, ++sequence);
						expires = Date.now() + 30 * 60 * 1000;
					}
					remember();
					return value;
				});
			};
		}).catch(() => {
			// Missing plugin/ACL/RPC must not break the normal wireless form.
		});
	}
});
