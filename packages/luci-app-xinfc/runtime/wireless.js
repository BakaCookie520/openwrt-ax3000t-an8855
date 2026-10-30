'use strict';
'require baseclass';
'require form';
'require rpc';
'require ui';
'require uci';

// No credentials in storage, RPC arguments, URLs or notifications.
// A successful LuCI apply confirmation, not a form save, authorizes the write.
// Partition intent by login session; never replay another user's browser intent.
const storageKey = 'xinfc-wireless-sync-v1-' + L.env.sessionid;
const fields = ['ssid', 'key', 'encryption'];
const pending = new Set();
let armed = null;
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
				sections: Array.from(pending), expires: expires
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
			.forEach(id => pending.add(id));
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

function chooseTarget(sections) {
	if (sections.length < 2 || sections.every(id =>
		credentials(id).every((value, index) => value === credentials(sections[0])[index])))
		return Promise.resolve(sections[0] || null);

	// There is one NFC tag. Never silently let the last edited radio win.
	return new Promise(resolve => {
		const select = E('select', { 'class': 'cbi-input-select', 'aria-label': _('NFC 目标网络') },
			sections.map(id => E('option', { value: id }, [
				(uci.get('wireless', id, 'ssid') || id) + ' (' + id + ')'
			])));
		ui.showModal(_('选择同时写入 NFC 的网络'), [
			E('p', {}, [_('多个无线接口的连接信息不同，但设备只有一个 NFC 标签。请选择要分享的网络；其他接口仍正常应用。')]),
			select,
			E('div', { 'class': 'right' }, [
				E('button', { 'class': 'cbi-button', click: function() {
					ui.hideModal(); resolve(null);
				} }, [_('取消应用')]),
				' ',
				E('button', { 'class': 'cbi-button cbi-button-action', click: function() {
					ui.hideModal(); resolve(select.value);
				} }, [_('继续应用并同步 NFC')])
			])
		]);
	});
}

const originalApply = ui.changes.apply;
ui.changes.apply = function() {
	const context = this, args = arguments;
	if (selecting)
		return Promise.resolve();
	armed = null;
	if (expires <= Date.now()) {
		pending.clear();
		remember();
	}
	if (!pending.size)
		return originalApply.apply(context, args);
	selecting = true;
	return uci.changes().then(changes => {
		const edits = changes.wireless || [];
		const candidates = Array.from(pending).filter(id => eligible(id) && edits.some(edit =>
			edit[1] === id && (fields.includes(edit[2]) || edit[0] === 'add')));
		// Expired/reverted/deleted/unsupported interfaces cannot cause later writes.
		pending.clear();
		candidates.forEach(id => pending.add(id));
		remember();
		if (!candidates.length) {
			originalApply.apply(context, args);
			return;
		}
		return chooseTarget(candidates).then(section => {
			if (!section)
				return;
			armed = section;
			return originalApply.apply(context, args);
		});
	}, () => {
		notify(_('无法核对待应用的无线变更，本次不自动写入 NFC；请在 NFC 页面检查。'), 'warning');
		return originalApply.apply(context, args);
	}).finally(() => { selecting = false; });
};

document.addEventListener('uci-reverted', function() {
	armed = null;
	pending.clear();
	remember();
});

document.addEventListener('uci-applied', function() {
	const section = armed;
	armed = null;
	if (!section)
		return;
	// Clear before RPC: a lost response must not trigger duplicate hardware writes.
	pending.clear();
	remember();
	callWrite(section, '', '', '').then(result => {
		if (!result.ok)
			throw new Error('NFC request rejected');
		notify(_('无线配置已应用，NFC 同步任务已提交。请到“服务 → AX3000T NFC”确认读回校验结果；请勿断电。'));
	}, () => {
		notify(_('无线配置已应用，但无法确认 NFC 同步请求是否收到。请检查 NFC 任务状态，不要立即重复写入。'), 'warning');
	}).catch(() => {
		notify(_('无线配置已应用，但 NFC 后台拒绝了同步。请在“服务 → AX3000T NFC”检查硬件、加密方式和名称／密码长度。'), 'warning');
	});
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
				_('默认勾选。仅在本页“保存并应用”成功确认后，将此接口的连接信息写入 NFC；仅保存或取消不写入。NFC 可被近距离读取。支持 WPA2-AES／WPA2-WPA3 混合、SSID 2–28 字节、密码 8–63 字节。'));
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
						pending.add(id);
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
