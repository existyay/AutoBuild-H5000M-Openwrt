'use strict';
'require view';
'require form';
'require fs';
'require ui';
'require uci';
'require poll';

// The page is a plain LuCI form over /etc/config/h5000m_accel, plus a status
// panel driven by /usr/sbin/h5000m-accel-status.  The status panel matters:
// it reports what the kernel is doing, so a switch that silently failed to take
// effect is visible rather than assumed.
return view.extend({
	load: function() {
		return Promise.all([
			uci.load('h5000m_accel'),
			uci.load('firewall')
		]);
	},

	status: function() {
		return fs.exec('/usr/sbin/h5000m-accel-status').then(function(res) {
			return (res.stdout || '').trim();
		}).catch(function() {
			return '';
		});
	},

	parse: function(text) {
		var out = {};
		(text || '').split(/\n/).forEach(function(line) {
			var i = line.indexOf('=');
			if (i > 0)
				out[line.substring(0, i)] = line.substring(i + 1);
		});
		return out;
	},

	render: function() {
		var m, s, o, self = this;
		var statusBox = E('div', { 'class': 'cbi-section' });

		var refresh = function() {
			return self.status().then(function(text) {
				var d = self.parse(text);
				var on = function(v) { return v === '1' ? '已启用' : '未启用'; };
				var rows = [
					[ '软件流量卸载', on(d.fw_flow_offloading) ],
					[ '硬件流量卸载', on(d.fw_flow_offloading_hw) ],
					[ 'PPE 卸载驱动', d.ppe_loaded === '1' ? '已加载' : '未加载' ],
					[ '拥塞控制', (d.tcp_congestion_control || '未知') + (d.bbr_active === '1' ? '（BBR 生效中）' : '') ],
					[ '流表条目', d.flow_entries || '0' ]
				];
				statusBox.replaceChildren(
					E('h3', {}, '当前状态'),
					E('table', { 'class': 'table' }, rows.map(function(r) {
						return E('tr', { 'class': 'tr' }, [
							E('td', { 'class': 'td', 'width': '35%' }, r[0]),
							E('td', { 'class': 'td' }, r[1])
						]);
					})),
					E('p', { 'class': 'cbi-section-descr' },
						'这些值来自内核与防火墙的实际状态，而不是配置里的期望值。' +
						'硬件卸载依赖 PPE 驱动；若它显示未加载，硬件卸载不会生效。')
				);
			});
		};

		m = new form.Map('h5000m_accel', '网络加速',
			'本页控制主线 OpenWrt 在这台设备上真正可用的加速手段。' +
			'主线没有 MTK HNAT，也没有 TurboACC —— 硬件加速走的是 PPE 经 netfilter 流表卸载，' +
			'也就是下面的硬件流量卸载开关。');

		s = m.section(form.NamedSection, 'settings', 'accel', '加速设置');
		s.anonymous = true;

		o = s.option(form.Flag, 'flow_offload', '软件流量卸载',
			'用 netfilter 流表绕过部分协议栈。占用少量内存，对转发吞吐有明显帮助。');
		o.rmempty = false;
		o.default = '1';

		o = s.option(form.Flag, 'flow_offload_hw', '硬件流量卸载',
			'把已建立的连接交给 PPE 处理。需要上面的软件卸载同时开启，' +
			'并且 PPE 驱动已加载，否则不产生任何效果。');
		o.rmempty = false;
		o.default = '1';

		o = s.option(form.Flag, 'bbr', 'BBR 拥塞控制',
			'改善高丢包、长肥管道下的 TCP 吞吐。核不支持时会自动跳过。');
		o.rmempty = false;
		o.default = '1';

		return m.render().then(function(node) {
			var wrapper = E('div', {}, [ statusBox, node ]);
			return refresh().then(function() {
				poll.add(refresh, 5);
				return wrapper;
			});
		});
	},

	// Apply the settings once UCI has been saved, then refresh the status panel.
	handleSaveApply: function(ev, mode) {
		var self = this;
		return this.handleSave(ev).then(function() {
			return fs.exec('/usr/sbin/h5000m-accel', [ 'apply' ]).catch(function() {});
		}).then(function() {
			return ui.changes.apply(mode === '0');
		}).then(function() {
			window.setTimeout(function() { location.reload(); }, 1500);
		});
	}
});
