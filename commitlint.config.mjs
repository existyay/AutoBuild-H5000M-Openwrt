// commitlint — enforces Conventional Commits on this repository.
//
// Why it matters for THIS project: the firmware is built automatically from
// master, so the commit log is the release log.  Release Please turns commit
// types into version bumps and changelog sections, which means a mislabelled
// commit becomes a wrong release note (a `feat:` that was really a `fix:`).
// Conventional Commits is the contract that makes that automation honest.
export default {
	extends: ['@commitlint/config-conventional'],
	rules: {
		// The project writes Chinese commit bodies; keep the type and scope
		// machine-readable and in English, and do not police the subject's
		// language.
		'type-enum': [
			2,
			'always',
			[
				'feat',     // new capability (new package, new option)
				'fix',      // bug fix (device-visible or build-visible)
				'docs',     // README / docs only
				'style',    // formatting, no behaviour change
				'refactor', // no behaviour change
				'perf',     // build time or runtime speed
				'test',     // test scripts / CI test wiring
				'build',    // build system, feeds, patches
				'ci',       // workflows, gates, rulesets
				'chore',    // maintenance
				'revert'
			]
		],
		// Scopes this project actually uses.  A free-form scope would drift
		// within a week and stop being greppable.
		'scope-enum': [
			2,
			'always',
			[
				'build',      // scripts/local-build.sh
				'ci',         // .github/workflows
				'security',   // supply chain, attestations
				'config',     // configs/
				'patches',    // patches/ and the fullcone chain
				'packages',   // local-packages/
				'feeds',      // feeds.conf.default, upstream/clone sources
				'kmods',      // kernel modules in the image
				'ebpf',       // Nikki-RS eBPF / BTF
				'fullcone',   // the four-layer fullcone chain
				'wwan',       // wwand / modem provisioning
				'wifi',       // wireless defaults
				'fan',        // fan control
				'accel',      // luci-app-h5000m-accel
				'docs',
				'release',
				'deps'
			]
		],
		'scope-empty': [1, 'never'],
		'subject-empty': [2, 'never'],
		// Do not force lower-case: the subjects are Chinese.
		'subject-case': [0],
		'header-max-length': [2, 'always', 120],
		'body-max-line-length': [0],
		'footer-max-line-length': [0]
	}
};
