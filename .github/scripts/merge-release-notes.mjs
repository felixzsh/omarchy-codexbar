import {execFileSync} from "node:child_process";
import {writeFileSync} from "node:fs";

const apiUrl = (process.env.GITHUB_API_URL || "https://api.github.com").replace(/\/$/, "");
const serverUrl = (process.env.GITHUB_SERVER_URL || "https://github.com").replace(/\/$/, "");
const token = process.env.GITHUB_TOKEN;
const repository = process.env.GITHUB_REPOSITORY;
const tag = process.env.RELEASE_TAG;
const releaseSha = process.env.RELEASE_SHA;
const compareHead = process.env.RELEASE_COMPARE_HEAD || tag;
const outputPath = process.env.RELEASE_NOTES_PATH || ".github/release-notes.md";

if (!token || !repository || !tag) {
  throw new Error("GITHUB_TOKEN, GITHUB_REPOSITORY and RELEASE_TAG are required");
}

const [owner, repo] = repository.split("/");
if (!owner || !repo) {
  throw new Error(`Invalid repository: ${repository}`);
}

const categoryOrder = ["Features", "Fixes", "Security", "Refactors", "Documentation", "Other Changes"];

function git(...args) {
  return execFileSync("git", args, {encoding: "utf8"}).trim();
}

function getPreviousTag() {
  try {
    return git("describe", "--tags", "--abbrev=0", `${tag}^`);
  } catch {
    return null;
  }
}

async function github(path, options = {}) {
  const response = await fetch(`${apiUrl}${path}`, {
    ...options,
    headers: {
      accept: "application/vnd.github+json",
      authorization: `Bearer ${token}`,
      "x-github-api-version": "2022-11-28",
      ...(options.headers || {})
    }
  });
  const text = await response.text();
  let data = null;

  if (text) {
    try {
      data = JSON.parse(text);
    } catch {
      data = text;
    }
  }

  if (!response.ok) {
    throw new Error(`GitHub API ${response.status} for ${path}: ${text.slice(0, 500)}`);
  }

  return data;
}

function parseConventionalCommit(subject) {
  const match = subject.match(/^([a-z][\w-]*)(?:\(([^()\r\n]+)\))?(!)?:\s+(.+)$/i);
  if (!match) return null;

  const type = match[1].toLowerCase();
  const scope = (match[2] || "").toLowerCase();
  let category = null;

  if (type === "feat") category = "Features";
  if (type === "fix") category = scope === "security" ? "Security" : "Fixes";
  if (type === "security") category = "Security";
  if (type === "refactor") category = "Refactors";

  if (!category) return null;

  return {
    category,
    breaking: Boolean(match[3]),
    scope,
    subject
  };
}

function escapeMarkdown(value) {
  return value
    .replaceAll("\\", "\\\\")
    .replaceAll("`", "\\`")
    .replaceAll("*", "\\*")
    .replaceAll("_", "\\_")
    .replaceAll("[", "\\[")
    .replaceAll("]", "\\]")
    .replaceAll("<", "\\<")
    .replaceAll(">", "\\>")
    .replaceAll("@", "\\@");
}

function commitUrl(sha) {
  return `${serverUrl}/${owner}/${repo}/commit/${sha}`;
}

function renderCommit(commit) {
  const subject = escapeMarkdown(commit.subject);
  const author = commit.author
    ? ` by @${commit.author}`
    : commit.authorName
      ? ` by ${escapeMarkdown(commit.authorName)}`
      : "";

  return `* ${subject}${author} in ${commitUrl(commit.sha)}`;
}

async function getCompareCommits(base, head) {
  const baseHead = `${encodeURIComponent(base)}...${encodeURIComponent(head)}`;
  const commits = [];

  for (let page = 1; ; page += 1) {
    const result = await github(
      `/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/compare/${baseHead}?per_page=100&page=${page}`
    );
    const pageCommits = result.commits || [];
    commits.push(...pageCommits);
    if (pageCommits.length < 100) break;
  }

  return commits;
}

async function hasAssociatedPullRequest(sha, cache) {
  if (cache.has(sha)) return cache.get(sha);

  const pullRequests = await github(
    `/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/commits/${encodeURIComponent(sha)}/pulls?per_page=100`
  );
  const result = pullRequests.length > 0;
  cache.set(sha, result);
  return result;
}

async function getDirectCommits(commits) {
  const associatedPullRequests = new Map();
  const directCommits = [];

  for (const commit of commits) {
    const subject = (commit.commit?.message || "").split("\n", 1)[0].trim();
    const parsed = parseConventionalCommit(subject);
    if (!parsed || await hasAssociatedPullRequest(commit.sha, associatedPullRequests)) continue;

    let author = commit.author?.login || null;
    let authorName = commit.commit?.author?.name || "";

    if (!author) {
      const details = await github(
        `/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/commits/${encodeURIComponent(commit.sha)}`
      );
      author = details.author?.login || null;
      authorName = details.commit?.author?.name || authorName;
    }

    directCommits.push({
      ...parsed,
      author,
      authorName,
      date: commit.commit?.author?.date || "",
      sha: commit.sha
    });
  }

  return directCommits.sort((a, b) => b.date.localeCompare(a.date));
}

function findTopLevelHeading(lines, start) {
  for (let index = start + 1; index < lines.length; index += 1) {
    if (/^## /.test(lines[index])) return index;
  }
  return lines.length;
}

function findFullChangelog(lines, start) {
  for (let index = start + 1; index < lines.length; index += 1) {
    if (lines[index].startsWith("**Full Changelog**")) return index;
  }
  return lines.length;
}

function findChangelogEnd(lines, start) {
  return Math.min(findTopLevelHeading(lines, start), findFullChangelog(lines, start));
}

function findCategoryEnd(lines, start) {
  for (let index = start + 1; index < lines.length; index += 1) {
    if (/^### /.test(lines[index]) || /^## /.test(lines[index]) || lines[index].startsWith("**Full Changelog**")) {
      return index;
    }
  }
  return lines.length;
}

function findCategoryHeading(lines, category, start, end = lines.length) {
  const heading = `### ${category}`;
  for (let index = start + 1; index < end; index += 1) {
    if (lines[index].trim() === heading) return index;
  }
  return -1;
}

function appendToCategory(lines, category, entries, changedIndex) {
  const headingIndex = findCategoryHeading(lines, category, changedIndex, findChangelogEnd(lines, changedIndex));
  if (headingIndex < 0) return false;

  let end = findCategoryEnd(lines, headingIndex);
  while (end > headingIndex && lines[end - 1].trim() === "") end -= 1;

  const insertion = [];
  if (lines[end - 1]?.trim()) insertion.push("");
  insertion.push(...entries, "");
  lines.splice(end, 0, ...insertion);
  return true;
}

function insertMissingCategories(lines, changesByCategory, changedIndex) {
  const missing = categoryOrder.filter(
    category => changesByCategory.get(category)?.length > 0 && findCategoryHeading(lines, category, changedIndex, findChangelogEnd(lines, changedIndex)) < 0
  );

  for (const category of missing.reverse()) {
    const categoryIndex = categoryOrder.indexOf(category);
    const end = findChangelogEnd(lines, changedIndex);
    let insertionIndex = end;

    for (let index = changedIndex + 1; index < end; index += 1) {
      const heading = lines[index].match(/^### (.+)$/)?.[1];
      if (heading && categoryOrder.indexOf(heading) > categoryIndex) {
        insertionIndex = index;
        break;
      }
    }

    lines.splice(insertionIndex, 0, "", `### ${category}`, "", ...changesByCategory.get(category), "");
  }
}

function mergeDirectCommits(body, directCommits) {
  if (directCommits.length === 0) return body;

  const lines = body.split("\n");
  let changedIndex = lines.findIndex(line => line.trim() === "## What's Changed");

  if (changedIndex < 0) {
    const anchor = Math.min(findTopLevelHeading(lines, -1), findFullChangelog(lines, -1));
    lines.splice(anchor, 0, "## What's Changed", "");
    changedIndex = anchor;
  }

  const changesByCategory = new Map();
  for (const category of categoryOrder) changesByCategory.set(category, []);
  for (const commit of directCommits) {
    changesByCategory.get(commit.category).push(renderCommit(commit));
  }

  for (const [category, entries] of changesByCategory) {
    if (entries.length > 0) appendToCategory(lines, category, entries, changedIndex);
  }
  insertMissingCategories(lines, changesByCategory, changedIndex);

  return lines.join("\n");
}

function getNewContributorUsernames(lines, start, end) {
  const section = lines.slice(start, end).join("\n");
  return new Set([...section.matchAll(/@([A-Za-z0-9-]+(?:\[bot\])?)/g)].map(match => match[1]));
}

function mergeNewContributors(body, directCommits) {
  if (directCommits.length === 0) return body;

  const lines = body.split("\n");
  let sectionIndex = lines.findIndex(line => line.trim() === "## New Contributors");
  const entries = new Map();
  for (const commit of directCommits) {
    if (commit.author && !entries.has(commit.author)) entries.set(commit.author, commit);
  }
  if (entries.size === 0) return body;

  if (sectionIndex < 0) {
    const changedIndex = lines.findIndex(line => line.trim() === "## What's Changed");
    const anchor = changedIndex >= 0
      ? findChangelogEnd(lines, changedIndex)
      : findFullChangelog(lines, -1);
    lines.splice(anchor, 0, "## New Contributors", "");
    sectionIndex = anchor;
  }

  const end = findChangelogEnd(lines, sectionIndex);
  const existing = getNewContributorUsernames(lines, sectionIndex, end);
  const additions = [...entries]
    .filter(([author]) => !existing.has(author))
    .map(([author, commit]) => `* @${author} made their first contribution in ${commitUrl(commit.sha)}`);

  if (additions.length === 0) return lines.join("\n");

  let insertionIndex = end;
  while (insertionIndex > sectionIndex && lines[insertionIndex - 1].trim() === "") insertionIndex -= 1;
  if (lines[insertionIndex - 1]?.trim()) lines.splice(insertionIndex, 0, "", ...additions, "");
  else lines.splice(insertionIndex, 0, ...additions, "");

  return lines.join("\n");
}

async function getFirstTimeDirectCommits(directCommits, previousTagDate) {
  const commitsByAuthor = new Map();
  for (const commit of directCommits) {
    if (commit.author && !commitsByAuthor.has(commit.author)) commitsByAuthor.set(commit.author, commit);
  }

  if (!previousTagDate) return [...commitsByAuthor.values()];

  const firstTime = [];
  for (const [author, commit] of commitsByAuthor) {
    const previousCommits = await github(
      `/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/commits?author=${encodeURIComponent(author)}&until=${encodeURIComponent(previousTagDate)}&per_page=1`
    );
    if (previousCommits.length === 0) firstTime.push(commit);
  }

  return firstTime;
}

async function main() {
  const previousTag = getPreviousTag();
  const previousTagDate = previousTag ? git("show", "-s", "--format=%cI", previousTag) : null;
  const compareBase = previousTag || git("rev-list", "--max-parents=0", tag).split("\n")[0];

  const generated = await github(`/repos/${owner}/${repo}/releases/generate-notes`, {
    method: "POST",
    headers: {"content-type": "application/json"},
    body: JSON.stringify({
      configuration_file_path: ".github/release.yml",
      previous_tag_name: previousTag || undefined,
      tag_name: tag,
      target_commitish: releaseSha
    })
  });

  const commits = await getCompareCommits(compareBase, compareHead);
  const directCommits = await getDirectCommits(commits);
  const firstTimeDirectCommits = await getFirstTimeDirectCommits(directCommits, previousTagDate);

  let body = mergeDirectCommits(generated.body, directCommits);
  body = mergeNewContributors(body, firstTimeDirectCommits);
  writeFileSync(outputPath, `${body.trimEnd()}\n`);

  console.log(`Prepared release notes for ${tag}: ${directCommits.length} direct commit(s) included`);
}

main().catch(error => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
