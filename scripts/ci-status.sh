#!/usr/bin/env bash
#
# ci-status.sh — 一眼看清当前 CI 的真实状态，并在失败时指出下一步。
#
# 为什么需要它：本项目有 6 个 workflow、多个 job，失败时要在 Actions 页面里
# 逐层点开才能定位。这个脚本把「最近一次运行的状态 / 哪个 job 失败 / 失败
# 步骤 / 怎么看日志 / 是否有 Required Check 缺失」集中打印出来，便于排错。
#
# Usage:
#   scripts/ci-status.sh            # 最近若干次运行
#   scripts/ci-status.sh <run-id>   # 某个 run 的详细状态与失败步骤
#
set -Eeuo pipefail

REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)}"
[ -n "$REPO" ] || {
	echo "无法确定仓库；请设置 REPO=owner/name" >&2
	exit 2
}
command -v gh >/dev/null 2>&1 || {
	echo "需要 gh CLI" >&2
	exit 2
}

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
red() { printf '\033[31m%s\033[0m\n' "$*"; }
grn() { printf '\033[32m%s\033[0m\n' "$*"; }
ylw() { printf '\033[33m%s\033[0m\n' "$*"; }

if [ $# -ge 1 ]; then
	run_id="$1"
	bold "== run ${run_id} =="
	gh api "repos/${REPO}/actions/runs/${run_id}" \
		--jq '"\(.name)  \(.status)/\(.conclusion // "-")  \(.head_sha[0:7])  \(.event)"
		      复现: gh run view \(.id) --log-failed"' || exit 1
	echo
	bold "-- 各 job 的失败步骤 --"
	gh api "repos/${REPO}/actions/runs/${run_id}/jobs" \
		--jq '.jobs[] | "\(.name): \(.conclusion // .status)"' 2>/dev/null || true
	echo
	gh api "repos/${REPO}/actions/runs/${run_id}/jobs" \
		--jq '.jobs[] | select(.conclusion=="failure") | .id' 2>/dev/null |
		while read -r jid; do
			[ -n "$jid" ] || continue
			bold "  job ${jid} 的失败步骤:"
			gh api "repos/${REPO}/actions/jobs/${jid}" \
				--jq '.steps[] | select(.conclusion=="failure") | "    ✗ \(.name)"' 2>/dev/null || true
		done
	echo
	bold "-- 失败诊断（若已产出）--"
	ylw "运行摘要里已有自动诊断；也可: gh run view ${run_id} --log-failed | tail -100"
	exit 0
fi

bold "== 最近 10 次运行（${REPO}）=="
gh run list --limit 10 \
	--json databaseId,workflowName,status,conclusion,headSha,event \
	--jq '.[] | "\(.databaseId)\t\(.workflowName)\t\(.status)/\(.conclusion // "-")\t\(.headSha[0:7])\t\(.event)"' |
	while IFS=$'\t' read -r id name st sha ev; do
		case "$st" in
			*/success) printf '  \033[32m%-10s\033[0m %-34s %s  %s\n' "$st" "$name" "$sha" "$ev" ;;
			*/failure) printf '  \033[31m%-10s\033[0m %-34s %s  %s\n' "$st" "$name" "$sha" "$ev" ;;
			*/cancelled) printf '  \033[33m%-10s\033[0m %-34s %s  %s\n' "$st" "$name" "$sha" "$ev" ;;
			*) printf '  %-10s %-34s %s  %s\n' "$st" "$name" "$sha" "$ev" ;;
		esac
	done

echo
bold "-- 分支保护要求的检查（缺失/未过即为合并阻塞原因）--"
rs_id="$(gh api "repos/${REPO}/rulesets" --jq '.[] | select(.name=="master-protection") | .id' 2>/dev/null || true)"
if [ -n "$rs_id" ]; then
	gh api "repos/${REPO}/rulesets/${rs_id}" \
		--jq '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context' 2>/dev/null |
		sed 's/^/  - /'
else
	ylw "  未找到 master-protection 规则集"
fi

echo
bold "-- 打开的 PR 及其门禁状态 --"
gh pr list --json number,title,mergeStateStatus,headRefName \
	--jq '.[] | "  #\(.number) [\(.mergeStateStatus)] \(.title) (\(.headRefName))"' 2>/dev/null || echo "  (无)"
echo
ylw "详细查看某次运行: scripts/ci-status.sh <run-id>"
