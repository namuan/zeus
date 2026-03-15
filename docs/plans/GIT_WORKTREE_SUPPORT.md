# RFC: Task-based Git Worktree Management

## 1. Overview

This RFC proposes a system for managing Git worktrees for tasks within projects. Each project is linked to a Git repository. Each task can optionally create an isolated Git worktree to allow parallel development, automated builds, or agent-based code execution without interfering with other tasks.

---

## 2. Goals

1. Enable **parallel task development** without branch conflicts.
2. Ensure **worktree isolation** for builds, tests, or automated agents.
3. Provide a **clean, centralized structure** for worktree management.
4. Allow **safe cleanup** of completed or abandoned tasks.
5. Be **scalable** to hundreds of tasks and multiple projects.

---

## 4. Terminology

| Term                        | Definition                                                                   |
| --------------------------- | ---------------------------------------------------------------------------- |
| **Repo**                    | A Git repository associated with a project.                                  |
| **Worktree**                | A Git working directory attached to a branch, created via `git worktree`.    |
| **Task**                    | A unit of work in the application, potentially associated with a Git branch. |
| **Base Worktree Directory** | Configurable root directory under which all task worktrees are created.      |

---

## 5. Worktree Lifecycle

### 5.1 Creation

1. Identify the **project repository** path:

   ```
   repo_path = {project_repo_path}
   ```

2. Determine **task branch name**:

   ```
   branch_name = task-{id}-{slug}
   ```

3. Determine **task worktree path**:

   ```
   worktree_path = {WORKTREE_BASE_PATH}/{project_slug}/{task_id}
   ```

4. Ensure project folder exists:

   ```bash
   mkdir -p {WORKTREE_BASE_PATH}/{project_slug}
   ```

5. Create worktree:

   ```bash
   git -C {repo_path} worktree add \
     {worktree_path} -b {branch_name} origin/main
   ```

6. Optional: Push branch to remote:

   ```bash
   git -C {repo_path} push -u origin {branch_name}
   ```

---

### 5.2 Usage

* Developers, automated agents, or background processes work inside the isolated task directory.
* Each worktree has its **own checked-out branch**, preventing conflicts with other tasks.
* All worktrees share the **same Git object database**, minimizing storage overhead.

---

### 5.3 Cleanup

1. After task completion:

   ```bash
   git -C {repo_path} worktree remove {worktree_path}
   ```

2. Delete the branch (if merged or abandoned):

   ```bash
   git -C {repo_path} branch -d {branch_name}
   ```

3. Optionally prune stale metadata:

   ```bash
   git -C {repo_path} worktree prune
   ```

---

## 6. Worktree Layout

```id="387gxy"
/worktrees
  project-a/
    task-101/
    task-102/
  project-b/
    task-7/
    task-8/
```

* `{WORKTREE_BASE_PATH}/{project_slug}/{task_id}` is the canonical path for all task worktrees.
* Projects and tasks are isolated from each other.

---

## 7. Configuration

| Config                | Description                         | Example      |
| --------------------- | ----------------------------------- | ------------ |
| `WORKTREE_BASE_PATH`  | Root folder for all worktrees       | `/worktrees` |
| `DEFAULT_BASE_BRANCH` | Branch to base new task branches on | `main`       |

---

## 8. Safety Considerations

* **One branch per worktree**: Git disallows the same branch in multiple worktrees.
* **Do not manually delete worktree folders**: always use `git worktree remove`.
* **Create intermediate directories** before adding a worktree (`mkdir -p`).
* **Periodic pruning** of stale worktrees ensures metadata integrity (`git worktree prune`).
