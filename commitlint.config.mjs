// commitlint — enforces Conventional Commits on this repository.
//
// Why it matters for THIS project: the firmware is built automatically from
// master, so the commit log is the release log.  Release Please turns commit
// types into version bumps and changelog sections, which means a mislabelled
// commit becomes a wrong release note (a `feat:` that was really a `fix:`).
// Conventional Commits is the contract that makes that automation honest.
export default {
	extends: ['@commitlint/config-conventional'],

	// Machine-generated commits are exempt from the human commit-message rules.
	//
	// This is not a loophole — it is the only way the gate can be strict about
	// what PEOPLE write while still letting the automation work:
	//
	//   * `Merge branch ...` — GitHub's "Update branch" button (and the
	//     update-branch API) creates a merge commit.  It has no type or scope
	//     because it is not authored content, and it disappears the moment the
	//     PR is squash-merged.  Measured: it failed this gate on the Release
	//     Please PR.
	//   * `chore(master): release X` — Release Please derives the scope from the
	//     BRANCH NAME, so the scope changes with the default branch and cannot
	//     be part of a fixed enum.  release-please.yml overrides the pattern to
	//     use `chore(release):` instead; this pattern is kept as defence for a
	//     repo whose Release Please config has not been updated yet.
	ignores: [
		(msg) => /^Merge (branch|remote-tracking|pull request)\b/.test(msg),
		(msg) => /^chore\([^)]*\): release\b/.test(msg),
		// GitHub's own web-flow commits when editing a file in the browser.
		(msg) => /^(Update|Create|Delete|Rename) /.test(msg)
	],

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
