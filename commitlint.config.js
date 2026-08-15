const RELEASE_VERSION = /^release \d+\.\d+\.\d+$/;

const isRelease = ({ type, subject }) =>
  type === "chore" && /^release(?:\s|$)/.test(subject ?? "");

// Types that can belong to the repo rather than to an addon, and so may go
// unscoped. Everything else — feat, fix, perf, refactor, revert, style, test —
// changes an addon by definition and has to name it.
const MAY_BE_UNSCOPED = new Set(["build", "chore", "ci", "docs"]);

export default {
  extends: ["@commitlint/config-conventional"],

  plugins: [
    {
      rules: {
        "scope-names-the-addon": (parsed) => {
          if (parsed.type === null || parsed.scope) return [true];
          if (MAY_BE_UNSCOPED.has(parsed.type) && !isRelease(parsed)) return [true];

          const reason = isRelease(parsed)
            ? "a release commit must name the addon being released"
            : `"${parsed.type}" changes an addon, so it must name one`;
          return [false, `${reason}, e.g. ${parsed.type}(markr): ${parsed.subject}`];
        },

        "release-subject-is-a-version": (parsed) => {
          if (!isRelease(parsed)) return [true];
          if (RELEASE_VERSION.test(parsed.subject ?? "")) return [true];
          return [
            false,
            `a release subject must read "release x.y.z", got "${parsed.subject}"`,
          ];
        },
      },
    },
  ],

  rules: {
    // One entry per addon directory. Grows as addons land. A scope is optional
    // for repo-level types, but when present it must name a real addon.
    "scope-enum": [2, "always", ["markr"]],
    "scope-names-the-addon": [2, "always"],
    "release-subject-is-a-version": [2, "always"],
  },
};
