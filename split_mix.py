import re
import os

with open('mix', 'r') as f:
    lines = f.readlines()

os.makedirs('src', exist_ok=True)

# We map module names to a list of section headers we want in them
module_map = {
    "header.sh": [None, "Config", "Tmux bootstrap", "Environment Detection"],
    "prompt.sh": ["System Prompt (rebuilt on each call to pick up caveman mode changes)", "Project-local extensions"],
    "tools.sh": ["Tools (OpenAI function calling)", "Tool Execution", "Risk Scoring: BLOCKED | HIGH | MED | LOW <reason>", "Ask user for confirmation (reads from /dev/tty, not stdin)", "Process one tool call", "Pre-edit diff preview", "Self-healing bash wrapper", "Auto-read logs on bash failure", "Wiki solutions writer"],
    "history.sh": ["History", "Auto-compact history"],
    "ui.sh": ["Spinner (background process)", "Context window % bar", "Tmux status updater"],
    "api.sh": ["API", "Response Parser", "Streaming API call", "Lightweight planning call (plan mode)"],
    "repl.sh": ["Agent Loop (one user turn → multi-turn tool use → final answer)", "REPL Commands", "Banner", "Main REPL"]
}

# Invert map for quick lookup
section_to_module = {}
for mod, secs in module_map.items():
    for sec in secs:
        section_to_module[sec] = mod

current_section = None
current_module = "header.sh"

module_contents = {mod: [] for mod in module_map.keys()}

for line in lines:
    m = re.match(r'^# ─── (.*?) ─+', line)
    if m:
        sec_name = m.group(1).strip()
        if sec_name in section_to_module:
            current_module = section_to_module[sec_name]
        else:
            # Group unknown headers into repl.sh or tools.sh
            pass
            
    module_contents[current_module].append(line)

for mod, content in module_contents.items():
    if content:
        with open(f'src/{mod}', 'w') as f:
            f.writelines(content)

# Now create build.sh
with open('build.sh', 'w') as f:
    f.write('''#!/usr/bin/env bash
cat src/header.sh \\
    src/prompt.sh \\
    src/history.sh \\
    src/tools.sh \\
    src/api.sh \\
    src/ui.sh \\
    src/repl.sh > mix.compiled
chmod +x mix.compiled
echo "Compiled to mix.compiled!"
''')
    
os.chmod('build.sh', 0o755)
print("Splitting complete.")
