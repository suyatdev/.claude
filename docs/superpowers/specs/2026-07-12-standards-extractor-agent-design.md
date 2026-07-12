# standards-extractor Subagent — Design

## Purpose

A global Claude Code subagent that extracts development guidelines, architectural
constraints, and coding standards from one or more provided PDF documents and
writes them out as clean, structured, actionable Markdown rule files. Extraction
only — this agent does not enforce the standards it extracts.

## Motivation

`VibeCodingRules/` in this repo already contains five PDFs (Agent Skills, Agent
Tools & Interoperability, Spec-Driven Production Grade Development, The New SDLC
With Vibe Coding, Vibe Coding Agent Security and Evaluation) whose normative
content should be turned into rule files consistent with the existing
`rules/*.md` convention used by this repo's `CLAUDE.md`.

## Location & Registration

- File: `~/.claude/agents/standards-extractor.md`
- Global scope: available in every project, since ingesting standards PDFs is a
  recurring, project-agnostic task.

## Frontmatter

```yaml
name: standards-extractor
description: Use this agent when the user provides one or more PDF documents containing development guidelines, architectural constraints, or coding standards, and wants their content extracted into clean, structured, actionable Markdown rule files. Do not use it for general PDF summarization unrelated to engineering standards.
tools: Read, Write, Bash, Glob
```

No `model` override — inherits the caller's model.

## Behavior

1. **Input resolution** — accept one or more PDF paths, or a directory to scan
   for PDFs (via `Glob`).
2. **Reading** — read each PDF in full. The `Read` tool caps PDF reads at 20
   pages per request, so chunk via the `pages` parameter for longer documents.
   Use `Bash` (`pdfinfo`/`mdls`) only if the page count needs to be discovered
   up front to plan the chunking.
3. **Filtering** — extract only genuinely normative content: actual rules,
   constraints, and conventions. Discard marketing copy, tables of contents,
   and narrative filler that carries no actionable rule.
4. **Classification** — group extracted rules into categories inferred from
   the content itself (e.g. Architecture, Coding Style, Testing, Security,
   Git/PR Workflow, Naming) rather than a fixed, hardcoded category list.
5. **Output style** — write one Markdown file per category, matching this
   repo's existing `rules/*.md` style: `# Title` → short intro → `##`
   subsections → bullet points with bold rule names, imperative/checkable
   phrasing, and the rationale alongside each rule where the source material
   gives one.
6. **Index** — write an `index.md` that links to every generated category
   file.
7. **Output directory** — always supplied by the caller in the invocation
   prompt. The agent never invents a default path; if none is given, it asks
   rather than guessing.
8. **Final report** — summarize files written, categories found, and any
   content skipped as non-normative or ambiguous.

## Out of scope

- Enforcing or checking code/diffs against the extracted standards (a
  separate concern, not built here).
- Any hardcoded default output directory.
- Any fixed, non-adaptive category taxonomy.

## Verification

Before opening a PR, run the agent against one PDF from `VibeCodingRules/`
(e.g. `Agent Skills_Day_3.pdf`) with an explicit output directory, and confirm
the generated Markdown is well-structured, faithful to the source, and
correctly split by category.
