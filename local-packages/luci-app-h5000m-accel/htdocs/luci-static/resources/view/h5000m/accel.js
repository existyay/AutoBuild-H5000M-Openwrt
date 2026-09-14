'use strict';
'require view';
'require form';
'require fs';
'require ui';
'require uci';
'require poll';

// A plain LuCI form over /etc/config/h5000m_accel, plus a status panel driven by
// /usr/sbin/h5000m-accel-status.
//
// The status panel is the point of the page.  It reports what the kernel is
// doing — not what the config asks for — so a switch that silently failed to
// take effect is visible, and the PPE line says which signal it matched rather
// than just asserting a state.
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

		var onoff = function(v) { return v === '1' ? '已启用' : '未启用'; };

		var refresh = function() {
			return self.status().then(function(text) {
				var d = self.parse(text);

				var ppeText;
				if (d.ppe_state === 'present')
					ppeText = '已就绪（' + (d.ppe_signal || '已检测到') + '）';
				else if (d.ppe_state === 'unknown')
					ppeText = '无法判定 —— 没有匹配到 mtk_ppe / mtk_soc_eth / mtk_wed 中的任何一个';
				else
					ppeText = '未检测到';

				var rows = [
					[ '软件流量卸载', onoff(d.fw_flow_offloading) ],
					[ '硬件流量卸载', onoff(d.fw_flow_offloading_hw) ],
					[ 'PPE 卸载驱动', ppeText ],
					[ '拥塞控制',
						(d.tcp_congestion_control || '未知') +
						(d.bbr_active === '1' ? '（BBR 生效中）'
							: d.bbr_available === '1' ? '（BBR 可用但未启用）'
							: '（内核未提供 BBR）') ],
					[ '已卸载连接', d.flow_entries || '0' ],
					[ '流表模块', (d.fw4_offload_kmod === '2' || d.fw4_offload_kmod === '1')
						? '已加载' : '未加载' ],
					[ 'Full-cone NAT', d.fullcone === '1'
						? '模块已加载，防火墙已按 fullcone 生成规则'
						: '模块未加载 —— 开关打开也不会生效' ]
				];

				var notes = [
					'以上是内核与防火墙的实际状态，不是配置里的期望值。',
					'硬件卸载依赖 PPE，并且必须与软件卸载同时开启；两者缺一，硬件卸载不会生效。'
				];

				if (d.fullcone === '1')
					notes.push('Full-cone NAT：模块已加载。');
				else
					notes.push('Full-cone NAT：主线 OpenWrt 不提供 nft-fullcone，内核也没有相应的 ' +
						'conntrack 支持，因此本页不提供该开关 —— 一个打开也不会有任何作用的开关，' +
						'比没有这个开关更糟。需要使用 full-cone 的场景，请改用具完整实现的第三方固件。');

				statusBox.replaceChildren(
					E('h3', {}, '当前状态'),
					E('table', { 'class': 'table' }, rows.map(function(r) {
						return E('tr', { 'class': 'tr' }, [
							E('td', { 'class': 'td', 'width': '30%' }, r[0]),
							E('td', { 'class': 'td' }, r[1])
						]);
					})),
					E('div', { 'class': 'cbi-section-descr' },
						notes.map(function(n) { return E('p', {}, n); }))
				);
			});
		};

		m = new form.Map('h5000m_accel', '网络加速',
			'本页控制主线 OpenWrt 在这台设备上真正可用的加速手段。' +
			'主线没有 MTK HNAT，也没有 TurboACC —— 硬件加速走的是 PPE 经 netfilter 流表卸载。');

		s = m.section(form.NamedSection, 'settings', 'accel', '加速模式');
		s.anonymous = true;

		o = s.option(form.ListValue, 'profile', '模式',
			'高性能：软件卸载 + 硬件卸载 + BBR，转发吞吐最好。<br />' +
			'兼容：只开软件卸载，硬件路径关闭 —— 个别应用在连接被卸载后行为异常时退回这里。<br />' +
			'自定义：以下三个开关按所写的值生效。');
		o.value('performance', '高性能');
		o.value('compat', '兼容');
		o.value('custom', '自定义');
		o.default = 'performance';
		o.rmempty = false;

		o = s.option(form.Flag, 'flow_offload', '软件流量卸载',
			'用 netfilter 流表绕过部分协议栈。硬件卸载的前提，也是唯一在所有场景下都安全的一项。');
		o.rmempty = false;
		o.default = '1';
		o.depends('profile', 'custom');

		o = s.option(form.Flag, 'flow_offload_hw', '硬件流量卸载',
			'把已建立的连接交给 PPE 处理。需要软件卸载同时开启，并且 PPE 驱动已就绪。');
		o.rmempty = false;
		o.default = '1';
		o.depends('profile', 'custom');

		o = s.option(form.Flag, 'fullcone', 'Full-cone NAT',
			'用 fullcone 取代 masquerade，并在 dstnat 链加入站恢复规则。' +
			'<br />UDP 的 NAT 类型变为 Full Cone，对 P2P、部分游戏和语音联机有帮助。' +
			'<br /><strong>这需要三样东西同时存在</strong>：内核模块 nft_fullcone、' +
			'打过 fullcone 补丁的 nftables 与 libnftnl、以及打过补丁的 firewall4。' +
			'本固件三者都已包含；若状态栏显示模块未加载，则开关不会产生任何效果。' +
			'<br />其它协议不受影响，行为与 masquerade 相同。');
		o.rmempty = false;
		o.default = '1';

		o = s.option(form.Flag, 'bbr', 'BBR 拥塞控制',
			'改善高丢包、长肥管道下的 TCP 吞吐。内核未提供 BBR 时会自动跳过并记录日志。');
		o.rmempty = false;
		o.default = '1';
		o.depends('profile', 'custom');

		return m.render().then(function(node) {
			var wrapper = E('div', {}, [ statusBox, node ]);
			return refresh().then(function() {
				poll.add(refresh, 5);
				return wrapper;
			});
		});
	},

	handleSaveApply: function(ev, mode) {
		return this.handleSave(ev).then(function() {
			return fs.exec('/usr/sbin/h5000m-accel', [ 'apply' ]).catch(function() {});
		}).then(function() {
			return ui.changes.apply(mode === '0');
		}).then(function() {
			window.setTimeout(function() { location.reload(); }, 1500);
		});
	}
});
