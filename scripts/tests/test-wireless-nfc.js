'use strict';
// Execute the actual LuCI module in a minimal browser/RPC sandbox, never hardware.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { execFileSync } = require('node:child_process');
const os = require('node:os');
const root = path.resolve(__dirname, '../..');
const source = fs.readFileSync(path.join(root, 'packages/luci-app-xinfc/runtime/wireless.js'), 'utf8');

function harness(settings = {}) {
	const data = {
		radio0: { '.type': 'wifi-device' }, radio1: { '.type': 'wifi-device' },
		ap0: { '.type': 'wifi-iface', mode: 'ap', device: 'radio0', ssid: 'home', key: 'secret-old', encryption: 'psk2' },
		ap1: { '.type': 'wifi-iface', mode: 'ap', device: 'radio1', ssid: 'guest', key: 'other-secret', encryption: 'sae-mixed' }
	};
	const events = {}, storage = settings.storage || new Map();
	const writes = [], notices = [], edits = [], applyModes = [], actions = [];
	let applied = 0, modal = null;
	const context = {
		console, Set, Date, Promise, JSON, Array,
		_: value => value,
		E: (tag, attrs, children) => ({ tag, attrs, children }),
		L: { hasViewPermission: () => !settings.readonly, env: { sessionid: settings.session || 'fixture-session' } },
		sessionStorage: {
			getItem: key => storage.get(key) || null,
			setItem: (key, value) => storage.set(key, value),
			removeItem: key => storage.delete(key)
		},
		document: { addEventListener: (event, fn) => { events[event] = fn; } },
		baseclass: { extend: value => value },
		form: { Flag: function() {} },
		uci: {
			get: (config, id, field) => field ? data[id]?.[field] : data[id],
			changes: () => settings.changesFailure ? Promise.reject(new Error('offline')) : Promise.resolve({ wireless: edits })
		},
		ui: {
			changes: { apply: function(checked) { applied++; applyModes.push(checked); actions.push('apply'); } },
			addNotification: (title, element, type) => notices.push({ element, type }),
			showModal: (title, body) => { modal = { title, body }; },
			hideModal: () => { modal = null; }
		},
		rpc: { declare: spec => (...args) => {
			if (spec.object === 'session') return Promise.resolve(settings.access !== false);
			if (spec.method === 'status') return settings.statusFailure ? Promise.reject(new Error('offline')) :
				Promise.resolve({ ok: true, supported: true, writer_available: true });
			writes.push(args);
			actions.push('write');
			if (settings.writeFailure) return Promise.reject(new Error('offline'));
			return Promise.resolve({ ok: !settings.writeRejected });
		} }
	};
	const integration = vm.runInNewContext('(function() {\n' + source + '\n})()', context);
	async function open(id = 'ap0') {
		let option;
		const section = {
			section: id,
			map: { save: function() {
				if (section.rejectSave) return Promise.reject(new Error('validation failed'));
				Object.assign(data[id], section.next || {});
				return Promise.resolve('saved');
			} },
			taboption: (tab, type, name, title, description) => {
				assert.equal(tab, 'encryption');
				assert.equal(title, '同时更改 NFC');
				option = { enabled: '1', disabled: '0', depends: () => {},
					isActive: () => true, formvalue: () => option.selected ?? '1' };
				return option;
			}
		};
		await integration.addOption(section);
		return { section, option };
	}
	async function save(id, values, selected = '1') {
		const item = await open(id);
		item.option.selected = selected;
		item.section.next = values;
		for (const field of Object.keys(values)) edits.push(['set', id, field, values[field]]);
		await item.section.map.save();
		return item;
	}
	async function event(name) {
		events[name]();
		for (let i = 0; i < 4; i++) await Promise.resolve();
	}
	return { data, edits, writes, notices, storage, open, save, event, applyModes, actions,
		apply: () => context.ui.changes.apply(true),
		get applied() { return applied; }, get modal() { return modal; } };
}

async function tests() {
	let h = harness();
	let item = await h.open();
	assert.equal(item.option.default, '1');
	assert.equal(item.option.cfgvalue(), '1');
	assert.equal(item.option.rmempty, false);
	await item.option.write('ap0', '1');
	assert.equal(h.writes.length, 0);
	await h.save('ap0', { key: 'new-secret-123' });
	assert.equal(h.writes.length, 0, 'Save must never write NFC');
	assert(![...h.storage.values()].join('').includes('new-secret'));
	assert(![...h.storage.values()].join('').includes('home'));
	await h.apply();
	assert.equal(h.applied, 1);
	assert.deepEqual(Array.from(h.writes[0]), ['', 'home', 'new-secret-123', 'psk2']);
	assert.deepEqual(h.applyModes, [false], 'NFC wireless sync must not start a checked-apply rollback');
	assert.deepEqual(h.actions, ['write', 'apply']);
	await h.apply();
	assert.equal(h.writes.length, 1, 'A consumed instruction cannot repeat NFC writes');
	assert.equal(h.storage.size, 0);
	console.log('ok: default checked; no write on open/save; current credentials are submitted before unchecked apply');

	for (const selected of ['0', '1']) {
		h = harness();
		await h.save('ap0', { key: 'updated-secret' }, selected);
		if (selected === '1') await h.event('uci-reverted');
		await h.apply();
		assert.equal(h.writes.length, 0, 'Unchecked/reverted intent must not write');
	}
	h = harness();
	item = await h.open();
	item.section.rejectSave = true;
	await assert.rejects(item.section.map.save());
	await h.apply();
	assert.equal(h.writes.length, 0);
	console.log('ok: unchecked, reverted, cancelled, failed-save and unconfirmed apply cannot write');

	for (const field of ['mode', 'disabled', 'encryption', 'ppsk']) {
		h = harness();
		h.data.ap0[field] = { mode: 'sta', disabled: '1', encryption: 'sae', ppsk: '1' }[field];
		await h.save('ap0', { key: 'updated-secret' });
		await h.apply();
		assert.equal(h.writes.length, 0);
	}
	for (const settings of [{ readonly: true }, { access: false }, { statusFailure: true }]) {
		h = harness(settings);
		assert.equal((await h.open()).option, undefined);
		assert.equal(h.writes.length, 0);
	}
	h = harness();
	await h.save('ap0', { channel: '36' });
	await h.apply();
	assert.equal(h.writes.length, 0);
	console.log('ok: only credential edits on eligible APs with NFC write permission are considered');

	h = harness();
	await h.save('ap0', { key: 'updated-secret' });
	await h.save('ap1', { ssid: 'different-network' });
	await h.apply();
	assert.equal(h.writes[0][0], '');
	assert.equal(h.writes[0][1], 'different-network');
	assert.equal(h.writes[0][2], 'other-secret');
	assert.equal(h.writes.length, 1);
	console.log('ok: latest edited network is selected without a multi-network prompt');

	h = harness();
	await h.save('ap1', { key: '5ghz-password' });
	await h.apply();
	assert.equal(h.writes[0][1], 'guest');
	assert.equal(h.writes[0][2], '5ghz-password');
	h = harness();
	await h.save('ap0', { key: '2ghz-password' });
	await h.apply();
	assert.equal(h.writes[0][1], 'home');
	assert.equal(h.writes[0][2], '2ghz-password');
	console.log('ok: changing only one band never submits the other band credentials');

	h = harness();
	await h.save('ap0', { key: 'updated-secret' });
	await h.save('ap1', { ssid: 'different-network' });
	await h.apply();
	assert.equal(h.writes[0][2], 'other-secret');
	h = harness();
	await h.save('ap0', { key: 'same-password' });
	await h.save('ap1', { ssid: 'home', key: 'same-password', encryption: 'psk2' });
	await h.apply();
	assert.equal(h.writes[0][2], 'same-password');
	assert.equal(h.writes.length, 1);
	console.log('ok: latest edited network wins; identical dual-band credentials still write once');

	h = harness();
	await h.save('ap0', { key: 'updated-secret' });
	let restored = harness({ storage: h.storage });
	restored.data.ap0.key = 'updated-secret';
	restored.edits.push(['set', 'ap0', 'key', 'updated-secret']);
	await restored.apply();
	assert.equal(restored.writes.length, 1);
	h = harness();
	await h.save('ap0', { key: 'first-passphrase' });
	await h.save('ap1', { key: 'second-passphrase' });
	await h.save('ap0', { key: 'last-passphrase' });
	restored = harness({ storage: h.storage });
	restored.data.ap0.key = 'last-passphrase';
	restored.data.ap1.key = 'second-passphrase';
	restored.edits.push(['set', 'ap0', 'key', 'last-passphrase'], ['set', 'ap1', 'key', 'second-passphrase']);
	await restored.apply();
	assert.equal(restored.writes[0][2], 'last-passphrase', 'Reload must preserve last-edit order');
	h = harness();
	await h.save('ap0', { key: 'updated-secret' });
	for (const settings of [{ session: 'another-login' }, { changesFailure: true }]) {
		restored = harness({ storage: new Map(h.storage), ...settings });
		restored.edits.push(['set', 'ap0', 'key', 'updated-secret']);
		await restored.apply();
		assert.equal(restored.writes.length, 0);
	}
	const expired = new Map(h.storage);
	for (const [key, value] of expired) {
		const saved = JSON.parse(value); saved.expires = 0;
		expired.set(key, JSON.stringify(saved));
	}
	restored = harness({ storage: expired });
	restored.edits.push(['set', 'ap0', 'key', 'updated-secret']);
	await restored.apply();
	assert.equal(restored.writes.length, 0);
	console.log('ok: saved intent survives same-login reload; different login, expiry or failed change check cannot write');

	for (const settings of [{ writeFailure: true }, { writeRejected: true }]) {
		h = harness(settings);
		await h.save('ap0', { ssid: 'updated-network' });
		await h.apply();
		assert.equal(h.applied, 1);
		assert.deepEqual(h.applyModes, [false]);
		assert.equal(h.writes.length, 1);
		assert.equal(h.storage.size, 0);
		assert(h.notices.some(notice => notice.type === 'warning'));
		assert.equal(h.writes.length, 1);
	}
	console.log('ok: NFC failure leaves Wi-Fi applied, reports uncertainty and never retries writes automatically');

	const work = fs.mkdtempSync(path.join(os.tmpdir(), 'xinfc-luci-'));
	try {
		const file = path.join(work, 'feeds/luci/modules/luci-mod-network/htdocs/luci-static/resources/view/network/wireless.js');
		fs.mkdirSync(path.dirname(file), { recursive: true });
		const original = "'require form';\nfunction edit(s) {\nreturn network.getWifiNetwork(s.section).then(function(radioNet) {\n" +
			"\t\t\t\tss.tab('encryption', _('Wireless Security'));\n});\n}\n";
		fs.writeFileSync(file, original);
		const configure = profile => execFileSync(process.env.PYTHON || (process.platform === 'win32' ? 'python' : 'python3'),
			[path.join(root, 'scripts/configure-wireless-nfc.py'), work, profile]);
		configure('full');
		let full = fs.readFileSync(file, 'utf8');
		assert(full.includes('await xinfcWireless.addOption(ss)'));
		new Function(full);
		configure('full');
		assert.equal(fs.readFileSync(file, 'utf8'), full);
		configure('recovery');
		assert.equal(fs.readFileSync(file, 'utf8'), original);
		fs.writeFileSync(file, original.replace('Wireless Security', 'Changed upstream'));
		assert.throws(() => configure('full'));
		assert(!fs.readFileSync(file, 'utf8').includes('xinfcWireless'));
		const upstreamAsync = original.replace('.then(function(radioNet)', '.then(async function(radioNet)');
		fs.writeFileSync(file, upstreamAsync);
		configure('recovery');
		assert.equal(fs.readFileSync(file, 'utf8'), upstreamAsync, 'Recovery must preserve upstream-owned async callbacks');
		assert.throws(() => configure('full'));
		fs.writeFileSync(file, original);
		configure('full');
		fs.writeFileSync(file, fs.readFileSync(file, 'utf8').replace('await xinfcWireless.addOption(ss);', 'changedHook(ss);'));
		assert.throws(() => configure('full'));
	}
	finally { fs.rmSync(work, { recursive: true, force: true }); }
	console.log('ok: source integration awaits ACL discovery, is idempotent/reversible, and rejects upstream drift');
}

tests().catch(error => { console.error(error); process.exitCode = 1; });
