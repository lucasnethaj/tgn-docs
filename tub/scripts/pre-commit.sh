#!/bin/sh

# Automatically format staged d files
# It automatically restages the files after formatting
# So if you stage a file then change it. Then that change will also be committed.

# install this by putting it in .git/hooks/ and making it executable or by running make instal-git-hooks
 
exec 1>&2
STAGED_DFILES=$(git diff --name-only --cached --diff-filter=ACM | grep '\.d$')
CHARS=$(echo STAGED_DFILES | wc -c)

if [[ ! $CHARS -eq 0 ]]; then
    dfmt -i $STAGED_DFILES;
    git add $STAGED_DFILES;
fi
