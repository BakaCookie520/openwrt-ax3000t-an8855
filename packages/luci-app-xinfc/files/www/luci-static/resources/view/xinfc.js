'use strict';
'require view';
'require rpc';
'require ui';
'require poll';

var callStatus = rpc.declare({
	object: 'luci.xinfc',
	method: 'status',
	expect: { '': {} }
});

var callWrite = rpc.declare({
	object: 'luci.xinfc',
	method: 'write',
	params: ['section', 'ssid', 'password', 'encryption'],
	expect: { '': {} }
});

function byteLength(value) {
	return new TextEncoder().encode(value).length;
}

function validateCredentials(ssid, password) {
	if (byteLength(ssid) < 2 || byteLength(ssid) > 28)
		return _('Wi-Fi 名称必须为 2–28 字节，中文通常占 3 字节。');
	if (byteLength(password) < 8 || byteLength(password) > 63)
		return _('Wi-Fi 密码必须为 8–63 字节。');
	if (/[\x00-\x1f\x7f]/.test(ssid + password))
		return _('名称和密码不能包含换行等控制字符。');
	return null;
}

// Scoped, offline-only styles. Leave the surrounding LuCI theme untouched.
var style = `
.xinfc-shell {
	--xn-accent:var(--primary,#5e72e4); --xn-link:var(--primary,#5e72e4);
	--xn-ink:var(--gray-dark,#32325d); --xn-muted:#6b7b8d;
	--xn-line:var(--lighter,#e9ecef); --xn-panel:#fff; --xn-soft:#f6f8fb;
	--xn-hero:#fff; --xn-warn-bg:#fff5ed; --xn-warn-ink:#995020;
	--xn-error-bg:#fce6eb; --xn-error-ink:#b42b49; --xn-on-accent:#fff;
	--xn-shadow:0 0 1rem rgba(136,152,170,.15);
	max-width:1180px; margin:0 auto; padding:12px 0 40px; color:var(--xn-ink);
	font-family:inherit;
	font-variant-numeric:tabular-nums; font-size:14px; line-height:1.65;
}
.xinfc-shell.is-dark {
	--xn-accent:var(--dark-primary,#483d8b); --xn-link:#b5bfff;
	--xn-ink:#ccc; --xn-muted:#adb5bd;
	--xn-line:#444; --xn-panel:#333; --xn-soft:#29292c;
	--xn-hero:#333; --xn-warn-bg:#3b3029; --xn-warn-ink:#f4be94;
	--xn-error-bg:#442c33; --xn-error-ink:#f3aabc; --xn-on-accent:#fff;
	--xn-shadow:0 0 .5rem rgba(0,0,0,.35);
	color-scheme:dark;
}
.xinfc-shell *, .xinfc-shell *:before, .xinfc-shell *:after {box-sizing:border-box}
.xinfc-shell h2, .xinfc-shell h3 {
	margin:0; padding:0; border:0; border-radius:0; background:none; box-shadow:none; color:var(--xn-ink);
	text-wrap:balance; line-height:1.4;
}
.xinfc-shell h3 {font-size:17px; font-weight:600}
.xinfc-shell p {margin:0}
.xinfc-shell section, .xinfc-shell aside, .xinfc-shell .xinfc-stack {min-width:0}
.xinfc-kicker {display:flex;align-items:center;gap:10px;color:var(--xn-muted);font-size:12px;font-weight:400}
.xinfc-hero {display:grid;grid-template-columns:minmax(0,1fr) auto;gap:24px;align-items:center;padding:22px 24px;background:var(--xn-hero);border-radius:.25rem;box-shadow:var(--xn-shadow);position:relative;overflow:hidden}
.xinfc-shell .xinfc-hero h2 {margin:8px 0 10px;font-size:25px;font-weight:600;letter-spacing:0;line-height:1.35}
.xinfc-hero-copy {max-width:40em;color:var(--xn-muted);font-size:14px}
.xinfc-hero-meta {display:grid;gap:10px;margin:0;padding:0;list-style:none;border-left:1px solid var(--xn-line);padding-left:24px}
.xinfc-meta-item {color:var(--xn-muted);font-size:12px;white-space:nowrap}
.xinfc-meta-item b {display:block;color:var(--xn-ink);font:600 15px/1.6 ui-monospace,Consolas,monospace}
.xinfc-grid {display:grid;grid-template-columns:minmax(0,1.5fr) minmax(280px,.8fr);gap:20px;margin-top:20px}
.xinfc-stack {display:grid;gap:20px;align-content:start}
.xinfc-shell .xinfc-card {margin:0;border:0;border-radius:.25rem;background:var(--xn-panel);box-shadow:var(--xn-shadow);line-height:1.65}
.xinfc-card-head {display:flex;justify-content:space-between;gap:16px;align-items:flex-start;padding:20px 24px 16px}
.xinfc-card-head>div {min-width:0}
.xinfc-card-note {margin-top:7px!important;color:var(--xn-muted);font-size:12px}
.xinfc-card-body {padding:0 24px 24px}
.xinfc-warning {display:grid;grid-template-columns:auto 1fr;gap:14px;margin-top:16px;padding:16px 20px;border-left:3px solid var(--warning,#fb6340);border-radius:.25rem;background:var(--xn-warn-bg);color:var(--xn-warn-ink)}
.xinfc-warning-mark {display:grid;place-items:center;width:24px;height:24px;border:1px solid currentColor;border-radius:.25rem;font:600 15px/1 ui-monospace,monospace}
.xinfc-warning strong {display:block;font-size:13px;font-weight:600}
.xinfc-warning p {margin-top:4px;font-size:12px}
.xinfc-status-grid {display:grid;grid-template-columns:1.1fr 1fr .9fr;margin:0 24px 24px;border-top:1px solid var(--xn-line);padding-top:17px}
.xinfc-status-cell {padding:0 16px;min-width:0}
.xinfc-status-cell:first-child {padding-left:0}
.xinfc-status-cell+.xinfc-status-cell {border-left:1px solid var(--xn-line)}
.xinfc-status-label {display:block;margin-bottom:5px;color:var(--xn-muted);font-size:12px}
.xinfc-status-value {display:block;font-size:13px;font-weight:600;line-height:1.5;overflow-wrap:anywhere}
.xinfc-mono {font-family:ui-monospace,Consolas,monospace}
.xinfc-badge {display:inline-flex;align-items:center;gap:8px;flex-shrink:0;padding:5px 9px;border-radius:.25rem;background:var(--xn-soft);color:var(--xn-link);font-size:12px;font-weight:600;line-height:1.5}
.xinfc-badge:before {content:"";width:6px;height:6px;flex:0 0 6px;border-radius:50%;background:currentColor}
.xinfc-badge.is-warning {background:var(--xn-warn-bg);color:var(--xn-warn-ink)}
.xinfc-badge.is-error {background:var(--xn-error-bg);color:var(--xn-error-ink)}
.xinfc-form {display:grid;gap:18px}
.xinfc-field {display:grid;gap:7px;min-width:0}
.xinfc-field label {font-size:13px;font-weight:600;line-height:1.5}
.xinfc-field-help {color:var(--xn-muted);font-size:12px}
.xinfc-shell .cbi-input-text, .xinfc-shell .cbi-input-select {
	width:100%;max-width:100%;min-width:0;min-height:40px;padding:8px 12px;
	border:1px solid var(--xn-line)!important;border-radius:.25rem;
	background-color:var(--xn-panel)!important;color:var(--xn-ink);
	font-family:inherit;font-size:14px;line-height:1.5;box-shadow:none;
	transition:border-color .2s,box-shadow .2s;
}
.xinfc-shell .cbi-input-select {padding-right:32px}
.xinfc-shell .cbi-input-text:focus, .xinfc-shell .cbi-input-select:focus {
	border-color:var(--xn-accent)!important;box-shadow:0 0 0 3px var(--xn-soft);outline:2px solid var(--xn-link);outline-offset:2px;
}
.xinfc-shell input:disabled, .xinfc-shell select:disabled {opacity:.6;cursor:not-allowed}
.xinfc-manual {display:grid;grid-template-columns:1fr 1fr;gap:16px}
.xinfc-manual .xinfc-field:last-child {grid-column:1/-1}
.xinfc-selection {padding:14px 16px;border-left:3px solid var(--xn-accent);background:var(--xn-soft);border-radius:.25rem;overflow-wrap:anywhere}
.xinfc-selection-name {display:block;font-weight:600}
.xinfc-selection-note {display:block;margin-top:4px;color:var(--xn-muted);font-size:12px}
.xinfc-action-row {display:flex;align-items:center;justify-content:space-between;gap:18px;border-top:1px solid var(--xn-line);padding-top:18px}
.xinfc-action-hint {color:var(--xn-muted);font-size:12px}
.xinfc-shell .xinfc-write {min-height:40px;flex-shrink:0;padding:8px 18px;border:1px solid var(--xn-accent);border-radius:.25rem;background:var(--xn-accent);color:var(--xn-on-accent);font-family:inherit;font-size:14px;font-weight:400;line-height:1.5;cursor:pointer;transition:transform .2s,filter .2s}
.xinfc-shell .xinfc-write:hover:not(:disabled) {filter:brightness(1.08);transform:translateY(-1px)}
.xinfc-shell .xinfc-write:active:not(:disabled) {transform:translateY(1px) scale(.985)}
.xinfc-shell button:focus-visible {outline:2px solid var(--xn-link);outline-offset:4px}
.xinfc-shell .xinfc-write:disabled {opacity:.5;cursor:not-allowed}
.xinfc-shell .xinfc-text-button {border:0;box-shadow:none;padding:6px 0;background:none;color:var(--xn-link);font:inherit;font-size:12px;cursor:pointer;text-underline-offset:4px}
.xinfc-text-button:hover {text-decoration:underline}
.xinfc-text-button:disabled {opacity:.5;cursor:wait}
.xinfc-log {min-height:180px;max-height:340px;margin:0;padding:16px;border:1px solid var(--xn-line);border-radius:.25rem;background:var(--xn-soft);color:var(--xn-ink);font:12px/1.8 ui-monospace,Consolas,monospace;white-space:pre-wrap;overflow:auto;overflow-wrap:anywhere}
.xinfc-log.is-empty {color:var(--xn-muted)}
.xinfc-footnote {color:var(--xn-muted);font-size:12px;line-height:1.75}
.xinfc-checklist {display:grid;gap:16px;margin:0;padding:0;list-style:none;counter-reset:check}
.xinfc-checklist li {display:grid;grid-template-columns:20px 1fr;gap:12px;font-size:13px}
.xinfc-checklist li:before {counter-increment:check;content:"0" counter(check);color:var(--xn-link);font:500 12px/1.8 ui-monospace,monospace}
.xinfc-checklist strong {display:block;font-weight:600}
.xinfc-checklist span {display:block;margin-top:3px;color:var(--xn-muted);font-size:12px}
.xinfc-backup-detail {margin-top:20px;padding-top:16px;border-top:1px solid var(--xn-line);font-size:12px;color:var(--xn-muted)}
.xinfc-backup-path {display:block;margin:6px 0;padding:0;border:0;border-radius:0;background:none;font:11px/1.7 ui-monospace,Consolas,monospace;color:var(--xn-ink);overflow-wrap:anywhere}
.xinfc-feedback {padding:12px 14px;border-radius:.25rem;background:var(--xn-error-bg);color:var(--xn-error-ink);font-size:13px}
.xinfc-shell [hidden] {display:none!important}
@media (max-width:1050px) {
	.xinfc-grid {grid-template-columns:minmax(0,1.3fr) minmax(260px,.9fr)}
	.xinfc-card-head {flex-wrap:wrap}
}
@media (max-width:820px) {
	.xinfc-shell {padding:0 0 28px}
	.xinfc-hero {grid-template-columns:1fr;padding:24px}
	.xinfc-hero-meta {grid-template-columns:1fr 1fr;border:0;padding:0;gap:20px}
	.xinfc-grid {grid-template-columns:1fr}
	.xinfc-card-head {padding:22px 20px 16px}
	.xinfc-card-body {padding:0 20px 22px}
	.xinfc-status-grid {margin:0 20px 22px}
}
@media (max-width:520px) {
	.xinfc-hero {padding:22px 20px}
	.xinfc-manual {grid-template-columns:1fr}
	.xinfc-manual .xinfc-field:last-child {grid-column:auto}
	.xinfc-status-grid {grid-template-columns:1fr;gap:12px}
	.xinfc-status-cell {display:flex;justify-content:space-between;gap:12px;padding:0}
	.xinfc-status-cell+.xinfc-status-cell {border:0}
	.xinfc-status-label {margin:0}
	.xinfc-action-row {align-items:stretch;flex-direction:column}
	.xinfc-shell .xinfc-write {width:100%!important;min-height:44px}
	.xinfc-shell .cbi-input-text, .xinfc-shell .cbi-input-select {min-height:44px}
	.xinfc-warning {padding:14px;gap:10px}
}
@media (prefers-reduced-motion:reduce) {.xinfc-shell * {transition:none!important}}
`;

function darkTheme() {
	// Follow the host theme, including Argon's forced-light/forced-dark mode.
	if (typeof document === 'undefined' || typeof getComputedStyle !== 'function')
		return false;
	var rgb = getComputedStyle(document.body).backgroundColor.match(/[\d.]+/g);
	return rgb && rgb.length >= 3 && (rgb.length < 4 || +rgb[3] > 0) &&
		(.2126 * rgb[0] + .7152 * rgb[1] + .0722 * rgb[2]) < 128;
}

return view.extend({
	load: function() {
		return callStatus().catch(function() { return {}; });
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null,

	render: function(data) {
		this.status = data;
		this.pending = false;
		this.readonly = !L.hasViewPermission();
		this.networks = (data.networks || []).filter(function(n) { return n.supported; });

		this.source = E('select', { 'class': 'cbi-input-select' },
			this.networks.map(function(n) {
				return E('option', { value: n.section }, [
					n.ssid + ' (' + n.section + ', ' + n.encryption + ')'
				]);
			}).concat([E('option', { value: '' }, [_('手动填写')])]));
		this.ssid = E('input', { 'class': 'cbi-input-text', type: 'text', autocomplete: 'off' });
		this.password = E('input', {
			'class': 'cbi-input-text', type: 'password', autocomplete: 'new-password'
		});
		this.encryption = E('select', { 'class': 'cbi-input-select' }, [
			E('option', { value: 'psk2' }, ['WPA2 Personal (AES)']),
			E('option', { value: 'sae-mixed' }, ['WPA2/WPA3 Personal'])
		]);
		this.source.id = 'xinfc-source';
		this.ssid.id = 'xinfc-ssid';
		this.password.id = 'xinfc-password';
		this.encryption.id = 'xinfc-encryption';
		this.manual = E('div', { 'class': 'xinfc-manual' }, [
			this.field(_('Wi-Fi 名称'), this.ssid, _('2–28 字节；中文通常占 3 字节')),
			this.field(_('Wi-Fi 密码'), this.password, _('8–63 字节；不会保存到无线配置')),
			this.field(_('认证方式'), this.encryption)
		]);
		this.source.addEventListener('change', L.bind(function() {
			this.setFeedback('');
			this.updateControls();
		}, this));
		this.ssid.addEventListener('input', L.bind(function() { this.setFeedback(''); }, this));
		this.password.addEventListener('input', L.bind(function() { this.setFeedback(''); }, this));
		this.badge = E('span', { 'class': 'xinfc-badge', role: 'status' });
		this.hardware = E('span', { 'class': 'xinfc-status-value xinfc-mono' });
		this.backup = E('span', { 'class': 'xinfc-status-value' });
		this.backupPath = E('code', { 'class': 'xinfc-backup-path' });
		this.access = E('span', { 'class': 'xinfc-status-value' });
		this.selectionName = E('span', { 'class': 'xinfc-selection-name' });
		this.selectionNote = E('span', { 'class': 'xinfc-selection-note' });
		this.selection = E('div', { 'class': 'xinfc-selection' }, [this.selectionName, this.selectionNote]);
		this.feedback = E('p', { 'class': 'xinfc-feedback', role: 'alert', hidden: true });
		this.actionHint = E('span', { 'class': 'xinfc-action-hint' });
		this.log = E('pre', {
			'class': 'xinfc-log', 'aria-label': _('刷写诊断输出'), tabindex: '0'
		});
		this.refreshing = false;
		this.refreshButton = E('button', {
			'class': 'xinfc-text-button', type: 'button',
			click: L.bind(this.refreshStatus, this)
		}, [_('刷新状态')]);
		this.writeButton = E('button', {
			'class': 'cbi-button cbi-button-action xinfc-write', type: 'button',
			click: L.bind(this.confirmWrite, this)
		}, [_('刷写 NFC')]);

		var page = E('main', { 'class': 'xinfc-shell' + (darkTheme() ? ' is-dark' : '') }, [
			E('style', {}, [style]),
			E('section', { 'class': 'xinfc-hero' }, [
				E('div', {}, [
					E('p', { 'class': 'xinfc-kicker' }, [_('服务 / NFC')]),
					E('h2', {}, [_('AX3000T NFC 管理')]),
					E('p', { 'class': 'xinfc-hero-copy' }, [
						_('写入 Wi-Fi 连接信息，让支持 WSC 的手机靠近即可读取。无需常驻服务，也不会改变路由器的无线配置。')
					])
				]),
				E('ul', { 'class': 'xinfc-hero-meta' }, [
					E('li', { 'class': 'xinfc-meta-item' }, [E('b', {}, ['0 / 0x57']), _('I²C 总线 / 地址')]),
					E('li', { 'class': 'xinfc-meta-item' }, [E('b', {}, ['160 bytes']), _('NDEF 数据区')])
				])
			]),
			E('div', { 'class': 'xinfc-warning' }, [
				E('span', { 'class': 'xinfc-warning-mark', 'aria-hidden': 'true' }, ['!']),
				E('div', {}, [
					E('strong', {}, [_('仅用于已确认 NFC 硬件匹配的 AX3000T。')]),
					E('p', {}, [
						_('型号检查不等于芯片身份验证。请确认 I²C 0 / 0x57 上是原项目测试的 NFC 芯片；未经验证的硬件批次不要刷写。NFC 内容可被近距离读取，建议优先分享访客网络。')
					])
				])
			]),
			E('div', { 'class': 'xinfc-grid' }, [
				E('div', { 'class': 'xinfc-stack' }, [
					E('section', { 'class': 'cbi-section xinfc-card' }, [
						E('div', { 'class': 'xinfc-card-head' }, [
							E('div', {}, [
								E('h3', {}, [_('设备与任务状态')]),
								E('p', { 'class': 'xinfc-card-note' }, [_('刷写前会再次检查设备型号、I²C 状态与任务锁。')])
							]),
							this.badge
						]),
						E('div', { 'class': 'xinfc-status-grid' }, [
							E('div', { 'class': 'xinfc-status-cell' }, [
								E('span', { 'class': 'xinfc-status-label' }, [_('接口')]),
								this.hardware
							]),
							E('div', { 'class': 'xinfc-status-cell' }, [
								E('span', { 'class': 'xinfc-status-label' }, [_('备份')]),
								this.backup
							]),
							E('div', { 'class': 'xinfc-status-cell' }, [
								E('span', { 'class': 'xinfc-status-label' }, [_('当前权限')]),
								this.access
							])
						])
					]),
					E('section', { 'class': 'cbi-section xinfc-card' }, [
						E('div', { 'class': 'xinfc-card-head' }, [
							E('div', {}, [
								E('h3', {}, [_('连接信息')]),
								E('p', { 'class': 'xinfc-card-note' }, [_('选择已保存的网络，或只在此处填写要写入 NFC 的凭据。')])
							])
						]),
						E('div', { 'class': 'xinfc-card-body xinfc-form' }, [
							this.field(_('配置来源'), this.source),
							E('p', { 'class': 'xinfc-footnote' }, [
								_('选择现有网络时，后台在刷写前读取已保存的 SSID 和密码，不会把原密码返回浏览器。')
							]),
							this.selection,
							this.manual,
							E('p', { 'class': 'xinfc-footnote' }, [
								_('只支持 WPA2 Personal / AES 和 WPA2/WPA3 混合模式；混合模式以 WPA2 写入。未保存的无线设置不会生效。')
							]),
							this.feedback,
							E('div', { 'class': 'xinfc-action-row' }, [
								this.actionHint,
								this.writeButton
							])
						])
					])
				]),
				E('aside', { 'class': 'xinfc-stack' }, [
					E('section', { 'class': 'cbi-section xinfc-card' }, [
						E('div', { 'class': 'xinfc-card-head' }, [
							E('div', {}, [
								E('h3', {}, [_('刷写日志')]),
								E('p', { 'class': 'xinfc-card-note' }, [_('仅显示设备输出，不包含 SSID 或密码。')])
							]),
							this.refreshButton
						]),
						E('div', { 'class': 'xinfc-card-body' }, [this.log])
					]),
					E('section', { 'class': 'cbi-section xinfc-card' }, [
						E('div', { 'class': 'xinfc-card-head' }, [
							E('div', {}, [
								E('h3', {}, [_('写入前检查')])
							])
						]),
						E('div', { 'class': 'xinfc-card-body' }, [
							E('ol', { 'class': 'xinfc-checklist' }, [
								E('li', {}, [E('div', {}, [
									E('strong', {}, [_('先确认芯片批次')]),
									E('span', {}, [_('型号检查不验证芯片身份；未知批次请勿刷写。')])
								])]),
								E('li', {}, [E('div', {}, [
									E('strong', {}, [_('优先分享访客网络')]),
									E('span', {}, [_('NFC 中的 Wi-Fi 密码可被近距离读取。')])
								])]),
								E('li', {}, [E('div', {}, [
									E('strong', {}, [_('等待读回校验完成')]),
									E('span', {}, [_('刷写期间请勿断电。失败可能留下不完整数据。')])
								])])
							]),
							E('div', { 'class': 'xinfc-backup-detail' }, [
								E('span', {}, [_('首次备份 · 仅 root 可读')]),
								this.backupPath,
								E('span', {}, [_('建议通过 SSH 另存备份。它不保证能修复锁定位或配置区。')])
							])
						])
					])
				])
			])
		]);
		this.applyStatus(data);
		poll.add(L.bind(this.refreshStatus, this), 2);
		return page;
	},

	field: function(title, control, help) {
		var id = control.id;
		var helper = help ? E('span', { 'class': 'xinfc-field-help', id: id + '-help' }, [help]) : null;
		if (helper)
			control.setAttribute('aria-describedby', id + '-help');
		var children = [
			E('label', { 'for': id }, [title]),
			control
		];
		if (helper)
			children.push(helper);
		return E('div', { 'class': 'xinfc-field' }, children);
	},

	setFeedback: function(message) {
		this.feedback.textContent = message;
		this.feedback.hidden = !message;
	},

	refreshStatus: function() {
		if (this.refreshing)
			return Promise.resolve();
		this.refreshing = true;
		this.refreshButton.disabled = true;
		return callStatus().then(L.bind(this.applyStatus, this)).catch(L.bind(function() {
			this.applyStatus({});
		}, this)).finally(L.bind(function() {
			this.refreshing = false;
			this.refreshButton.disabled = false;
		}, this));
	},

	applyStatus: function(status) {
		this.status = status;
		var phases = {
			idle: _('等待刷写'),
			running: _('正在刷写，请勿断电'),
			success: _('刷写成功，数据已读回校验'),
			error: _('刷写失败或任务中断，请查看日志')
		};
		var failure = !status.ok || status.phase === 'error';
		var warning = !status.supported || !status.i2c_available || !status.writer_available ||
			!status.runtime_available || status.driver_busy || status.busy || status.phase === 'running';
		this.badge.className = 'xinfc-badge' + (failure ? ' is-error' : warning ? ' is-warning' : '');
		this.badge.textContent = !status.ok ? _('后台连接不可用') :
			!status.supported ? _('非支持的 AX3000T，禁止刷写') :
			!status.i2c_available ? _('I²C 接口缺失，禁止刷写') :
			!status.writer_available ? _('底层刷写程序缺失，禁止刷写') :
			!status.runtime_available ? _('任务目录不可用，禁止刷写') :
			status.driver_busy ? _('NFC 芯片已被内核驱动占用，禁止直接刷写') :
			(phases[status.phase] || _('状态未知'));
		this.hardware.textContent = 'I²C 0 · 0x57';
		this.backup.textContent = !status.ok ? _('暂时未知') :
			status.backup_available ? _('首次备份已保留') : _('首次写入时创建');
		this.backupPath.textContent = status.backup_path || '/etc/xinfc/nfc_ndef_backup.bin';
		this.access.textContent = this.readonly ? _('只读') : _('可刷写');
		// textContent, never innerHTML: device diagnostics cannot inject markup.
		this.log.textContent = status.log || (!status.ok ?
			_('连接后台失败。\n请检查登录会话或点击“刷新状态”。') :
			_('暂无刷写记录。\n\n任务开始后，设备输出将在这里显示。\n状态每 2 秒自动更新。'));
		this.log.className = 'xinfc-log' + (status.log ? '' : ' is-empty');
		this.updateControls();
	},

	updateControls: function() {
		var busy = this.pending || !!this.status.busy;
		var blocked = this.readonly || busy;
		this.manual.style.display = this.source.value === '' ? '' : 'none';
		this.selection.hidden = this.source.value === '';
		var selected = this.networks.find(L.bind(function(n) { return n.section === this.source.value; }, this));
		this.selectionName.textContent = selected ? selected.ssid : '';
		this.selectionNote.textContent = selected ?
			selected.encryption + _(' · 密码由后台读取，不会返回浏览器') : '';
		this.actionHint.textContent = this.readonly ? _('当前会话为只读，不能刷写。') :
			busy ? _('正在处理任务，请勿断电或重复提交。') :
			!this.status.ok ? _('连接恢复后才可刷写；不要重复提交。') :
			_('点击后需再次确认。完成后自动读回校验。');
		this.source.disabled = blocked;
		this.ssid.disabled = blocked;
		this.password.disabled = blocked;
		this.encryption.disabled = blocked;
		this.writeButton.disabled = blocked || !this.status.ok ||
			!this.status.supported || !this.status.i2c_available ||
			this.status.driver_busy ||
			!this.status.writer_available || !this.status.runtime_available;
	},

	confirmWrite: function() {
		if (this.writeButton.disabled)
			return;
		var section = this.source.value;
		var ssid = section ? '' : this.ssid.value;
		var password = section ? '' : this.password.value;
		var encryption = section ? '' : this.encryption.value;
		var error = section ? null : validateCredentials(ssid, password);
		if (error) {
			this.setFeedback(error);
			return;
		}
		var selected = this.networks.find(function(n) { return n.section === section; });
		ui.showModal(_('确认刷写 NFC'), [
			E('p', {}, [
				_('将覆盖 NFC 中的连接信息，目标网络：') + (selected ? selected.ssid : ssid)
			]),
			E('p', {}, [_('请确认芯片匹配。密码将可被近距离读取；刷写期间请勿断电。')]),
			E('div', { 'class': 'right' }, [
				E('button', { 'class': 'cbi-button', click: ui.hideModal }, [_('取消')]),
				' ',
				E('button', {
					'class': 'cbi-button cbi-button-action',
					click: L.bind(function(ev) {
						ev.currentTarget.disabled = true;
						ui.hideModal();
						this.submitWrite(section, ssid, password, encryption);
					}, this)
				}, [_('确认并刷写')])
			])
		]);
	},

	submitWrite: function(section, ssid, password, encryption) {
		if (this.pending || this.status.busy)
			return;
		this.pending = true;
		this.setFeedback('');
		this.updateControls();
		return callWrite(section, ssid, password, encryption).then(L.bind(function(result) {
			if (!result.ok)
				throw new Error(result.error || _('后台拒绝了刷写请求。'));
			this.password.value = '';
			ui.addNotification(null, E('p', {}, [_('任务已启动，请等待读回校验结果。')]), 'info');
		}, this)).catch(L.bind(function(error) {
			this.setFeedback(error.message || _('请求失败；请先检查任务状态，不要立即重复刷写。'));
			ui.addNotification(null, E('p', {}, [
				error.message || _('请求失败；请先检查任务状态，不要立即重复刷写。')
			]), 'error');
		}, this)).then(L.bind(function() {
			return callStatus().then(L.bind(this.applyStatus, this));
		}, this)).catch(L.bind(function() {
			this.applyStatus({});
		}, this)).finally(L.bind(function() {
			this.pending = false;
			this.updateControls();
		}, this));
	}
});
