#!/bin/bash

# Script to check if drone_racer submodule can be pushed to main directly

set -e

SUBMODULE_PATH="drone_racer"
REMOTE_NAME="origin"
BRANCH_NAME="main"

echo "========================================"
echo "Checking drone_racer submodule status..."
echo "========================================"

# (1) Check if submodule exists
echo "(1) Checking submodule exists..."
if [ ! -d "$SUBMODULE_PATH" ]; then
    echo "    Error: Submodule '$SUBMODULE_PATH' does not exist."
    exit 1
fi
echo "    OK: Submodule found"

cd "$SUBMODULE_PATH"

# (2) Fetch remote and get commit info
echo "(2) Fetching remote and comparing commits..."
git fetch "$REMOTE_NAME" "$BRANCH_NAME" >/dev/null 2>&1 || true

CURRENT_COMMIT=$(git rev-parse HEAD)
REMOTE_MAIN_COMMIT=$(git rev-parse "$REMOTE_NAME/$BRANCH_NAME")
CURRENT_COMMIT_SHORT=$(git log -1 --oneline $CURRENT_COMMIT | cut -d' ' -f1)
REMOTE_MAIN_SHORT=$(git log -1 --oneline $REMOTE_MAIN_COMMIT | cut -d' ' -f1)

echo "    Current HEAD: $CURRENT_COMMIT_SHORT"
echo "    Remote $BRANCH_NAME: $REMOTE_MAIN_SHORT"

# (3) Determine relationship and act accordingly
echo "(3) Determining if push is possible..."

if git merge-base --is-ancestor "$REMOTE_NAME/$BRANCH_NAME" HEAD 2>/dev/null; then
    # Case A: HEAD is ahead - can push directly (fast-forward)
    COMMITS_AHEAD=$(git rev-list --count "$REMOTE_NAME/$BRANCH_NAME"..HEAD)
    echo ""
    echo "    => CAN PUSH to $REMOTE_NAME/$BRANCH_NAME (fast-forward)"
    echo "    => $COMMITS_AHEAD commit(s) ahead"
    echo ""
    echo "    Commits to push:"
    git log --oneline "$REMOTE_NAME/$BRANCH_NAME"..HEAD | sed 's/^/      /'
    echo ""
    read -p "    Push now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git checkout "$BRANCH_NAME" 2>/dev/null || git checkout -b "$BRANCH_NAME" "$REMOTE_NAME/$BRANCH_NAME"
        git merge "$CURRENT_COMMIT" --ff-only
        git push "$REMOTE_NAME" "$BRANCH_NAME"
        echo "    Done: Pushed to $REMOTE_NAME/$BRANCH_NAME"
    fi

elif git merge-base --is-ancestor HEAD "$REMOTE_NAME/$BRANCH_NAME" 2>/dev/null; then
    # Case B: HEAD is behind - need to pull
    COMMITS_BEHIND=$(git rev-list --count HEAD.."$REMOTE_NAME/$BRANCH_NAME")
    echo ""
    echo "    => CANNOT PUSH: BEHIND by $COMMITS_BEHIND commit(s)"
    echo ""
    echo "    Reason: Local is behind remote"
    echo ""
    echo "    To fix:"
    echo "      cd $SUBMODULE_PATH"
    echo "      git fetch $REMOTE_NAME"
    echo "      git rebase $REMOTE_NAME/$BRANCH_NAME"

else
    # Case C: Diverged - need to rebase/merge
    echo ""
    echo "    => CANNOT PUSH: DIVERGED from $REMOTE_NAME/$BRANCH_NAME"
    echo ""
    echo "    Reason: Histories have forked"
    echo ""
    echo "    Local commits (not in remote):"
    git log --oneline "$REMOTE_MAIN_COMMIT..HEAD" 2>/dev/null | sed 's/^/      /' || echo "      (none)"
    echo ""
    echo "    Remote commits (not in local):"
    git log --oneline "HEAD..$REMOTE_MAIN_COMMIT" 2>/dev/null | sed 's/^/      /' || echo "      (none)"
    echo ""
    echo "    To fix:"
    echo "      cd $SUBMODULE_PATH"
    echo "      git checkout $BRANCH_NAME"
    echo "      git rebase $REMOTE_NAME/$BRANCH_NAME"
fi
