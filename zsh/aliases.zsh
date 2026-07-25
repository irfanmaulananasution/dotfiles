alias reload="omz reload"

# Shortcuts
alias dotfiles="cd $DOTFILES"
alias projects="cd $HOME/Code"

# Copy public SSH key
alias copyssh="pbcopy < $HOME/.ssh/id_ed25519.pub"

# Flush DNS
alias flushdns="dscacheutil -flushcache && sudo killall -HUP mDNSResponder"

# Shrug
alias shrug="echo '¯\_(ツ)_/¯' | pbcopy"

# List with details
alias ll="ls -lahF"

# Quick navigation
alias ~="cd ~"
alias ..="cd .."
alias ...="cd ../.."