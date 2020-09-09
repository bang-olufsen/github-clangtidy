#!/bin/bash
set -e

# GITHUB_TOKEN is a GitHub private access token configured for repo:status scope
# DROPBOX_TOKEN is an access token for the Dropbox API

CLANGTIDY=${CLANGTIDY:="run-clang-tidy-10"}
BRANCH=${BRANCH:="origin/master"}

if [ "$GITHUB_ACTIONS" = "true" ]; then
  REPO_NAME=$(basename "$GITHUB_REPOSITORY")
  REPO_FULL_NAME=$GITHUB_REPOSITORY
  if [ "$(echo "$GITHUB_REF" | cut -d '/' -f4)" = "merge" ]; then
    PULL_REQUEST=$(echo "$GITHUB_REF" | cut -d '/' -f3)
  fi
fi

status () {
  if [ "$SHIPPABLE" = "true" ] || [ "$GITHUB_ACTIONS" = "true" ]; then
    if [ "$PULL_REQUEST" != "" ]; then
      DESCRIPTION=$(echo "$2" | cut -b -100)
      DATA="{ \"state\": \"$1\", \"description\": \"$DESCRIPTION\", \"context\": \"github / clangtidy\"}"
      PULL_REQUEST_STATUS=$(curl -s -H "Content-Type: application/json" -H "Authorization: token $GITHUB_TOKEN" -H "User-Agent: $REPO_FULL_NAME" -X GET "https://api.github.com/repos/$REPO_FULL_NAME/pulls/$PULL_REQUEST")
      STATUSES_URL=$(echo "$PULL_REQUEST_STATUS" | jq -r '.statuses_url')
      curl -H "Content-Type: application/json" -H "Authorization: token $GITHUB_TOKEN" -H "User-Agent: $REPO_FULL_NAME" -X POST -d "$DATA" "$STATUSES_URL" 1>/dev/null 2>&1
    fi

    if [ "$ANALYSE_ALL" = true ] && [ "$1" != "pending" ]; then
      BADGE_COLOR=red
      if [ "$ERRORS" -eq 0 ]; then
        BADGE_COLOR=yellow
        if [ "$WARNINGS" -eq 0 ]; then
          BADGE_COLOR=brightgreen
        fi
      fi

      BADGE_TEXT=$BUGS"_bug"$(test "$BUGS" -eq 1 || echo s)
      wget -O /tmp/clangtidy_"${REPO_NAME}"_"${BRANCH}".svg https://img.shields.io/badge/clangtidy-"$BADGE_TEXT"-"$BADGE_COLOR".svg 1>/dev/null 2>&1
      curl -X POST "https://api-content.dropbox.com/2/files/upload" \
        -H "Authorization: Bearer $DROPBOX_TOKEN" \
        -H "Content-Type: application/octet-stream" \
        -H "Dropbox-API-Arg: {\"path\": \"/clangtidy_${REPO_NAME}_${BRANCH}.svg\", \"mode\": \"overwrite\"}" \
        --data-binary @/tmp/clangtidy_"${REPO_NAME}"_"${BRANCH}".svg 1>/dev/null 2>&1
    fi
  fi

  echo "$2"
}

ARGS=("$@")
FILES=${ARGS[${#ARGS[@]}-1]}
unset "ARGS[${#ARGS[@]}-1]"

ANALYSE_ALL=false
if [ "$FILES" = "diff" ]; then
  FILES=$(git diff --name-only --diff-filter ACMRTUXB "$BRANCH" | grep -e '\.c$' -e '\.cc$' -e '\cpp$' -e '\.cxx$' | xargs)
elif [ "$FILES" = "." ]; then
  FILES=""
  ANALYSE_ALL=true
fi

status "pending" "Running $CLANGTIDY with args ${ARGS[*]} $FILES"

ERRORS=0
WARNINGS=0

if [ "$FILES" != "" ] || [ "$ANALYSE_ALL" = true ]; then
  LOG=/tmp/clangtidy.log
  COMMAND="python3 /usr/bin/$CLANGTIDY ${ARGS[*]} $FILES"
  $COMMAND 2>&1 | tee "$LOG"

  ERRORS=$(grep -c "error:" $LOG)
  WARNINGS=$(grep -c "warning:" $LOG)
fi

BUGS=$((ERRORS + WARNINGS ))
DESCRIPTION="Found $ERRORS errors and $WARNINGS warnings"

if [ "$BUGS" -eq 0 ]; then
  status "success" "$DESCRIPTION"
else
  status "failure" "$DESCRIPTION"
fi
