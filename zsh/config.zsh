setopt AUTO_CD
setopt CORRECT
setopt EXTENDED_HISTORY         # record timestamp with each entry
setopt HIST_IGNORE_DUPS         # don't record twice in a row
setopt HIST_FIND_NO_DUPS        # search skips duplicate entries
setopt HIST_IGNORE_SPACE        # commands starting with space aren't recorded (safety net: ` <secret-cmd>` stays out of history)
setopt HIST_REDUCE_BLIPS        # trim superfluous entries (e.g. blanks)
setopt HIST_VERIFY               # show expanded history line before running (recalls args for editing)
setopt SHARE_HISTORY            # share history across sessions, append immediately