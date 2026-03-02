# Quickstart: Fix Install Script, Sub Agent Consistency, and README

**Branch**: `001-fix-install-subagents` | **Date**: 2026-03-01

## Overview

This feature is a consistency and correctness pass across the simpsons-loops project. No new functionality is added. The work consists of updating terminology, aligning failure handling behavior with the spec, and ensuring the README accurately describes the project.

## Changes at a Glance

### 1. Terminology Fix: "Task tool" -> "Agent tool"

**Files already remediated** (4 files -- T012-T015 VERIFIED COMPLETE):
- ~~`speckit.homer.clarify.md` -- 2 occurrences~~ DONE
- ~~`speckit.lisa.analyze.md` -- 2 occurrences~~ DONE
- ~~`speckit.ralph.implement.md` -- 2 occurrences~~ DONE
- ~~`speckit.pipeline.md` -- 3 occurrences (including "Task tool call" -> "Agent tool call")~~ DONE

**Files remaining** (1 file -- tracked by T034):
- `README.md` -- 2 occurrences

**What to do**: Find-and-replace "Task tool" with "Agent tool" in `README.md`.

### 2. Failure Handling: No Retry in Loop Commands

**Files already remediated** (3 files -- T016-T018 VERIFIED COMPLETE):
- ~~`speckit.homer.clarify.md`~~ DONE -- already uses immediate abort with error context logging
- ~~`speckit.lisa.analyze.md`~~ DONE -- already uses immediate abort with error context logging
- ~~`speckit.ralph.implement.md`~~ DONE -- already uses immediate abort with error context logging

**Do NOT change** (4 files):
- `homer-loop.sh`, `lisa-loop.sh`, `ralph-loop.sh`, `pipeline.sh` -- bash scripts keep their retry behavior.

### 3. Pipeline Failure Handling

**File to change**: `speckit.pipeline.md`

**What to do**: Add explicit failure handling instructions for each pipeline step, consistent with the no-retry policy for loop commands.

### 4. README Updates

**File to change**: `README.md`

**What to do**:
- Replace "Task tool" with "Agent tool" (2 occurrences)
- Update the permission note to clarify that loop commands instruct sub agents to execute autonomously
- Verify all file paths match actual repository contents

### 5. Setup Script Verification

**File to verify**: `setup.sh`

**What to do**: Verify idempotency and test directory behavior. The script is already largely compliant. Confirm error messages match spec wording.

## Verification Checklist

After implementing all changes:

1. `grep -r "Task tool" *.md agents/*.md` returns zero results
2. No loop command file mentions "Abort after 3 consecutive failures"
3. All loop command files reference "Agent tool" with `subagent_type: general-purpose`
4. README terminology matches loop command files
5. `setup.sh` runs successfully against a test directory with `.claude/` and `.specify/`
6. `setup.sh` is idempotent (run twice, same result)
7. All file paths in README correspond to actual files in the repository
