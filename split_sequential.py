import re
import os

with open('mix', 'r') as f:
    lines = f.readlines()

os.makedirs('src', exist_ok=True)

# Keep track of exactly what order they appeared
chunks = []
current_chunk_idx = 0

current_chunk = {"name": f"{current_chunk_idx:02d}_header.sh", "content": []}
chunks.append(current_chunk)

for line in lines:
    m = re.match(r'^# ─── (.*?) ─+', line)
    if m:
        sec_name = m.group(1).strip()
        # Clean section name to make an OK filename
        clean_name = re.sub(r'[^a-zA-Z0-9]+', '_', sec_name).strip('_').lower()
        if not clean_name:
            clean_name = "section"
        
        current_chunk_idx += 1
        current_chunk = {"name": f"{current_chunk_idx:02d}_{clean_name}.sh", "content": []}
        chunks.append(current_chunk)

    current_chunk["content"].append(line)

build_lines = ["#!/usr/bin/env bash\n", "cat \\\n"]

for i, chunk in enumerate(chunks):
    if chunk["content"]:
        with open(f'src/{chunk["name"]}', 'w') as f:
            f.writelines(chunk["content"])
        build_lines.append(f"    src/{chunk['name']} " + ("\\\n" if i < len(chunks)-1 else "> mix.compiled\n"))

with open('build.sh', 'w') as f:
    f.writelines(build_lines)
    f.write('chmod +x mix.compiled\n')
    f.write('echo "Compiled to mix.compiled!"\n')

os.chmod('build.sh', 0o755)
print("Sequential split complete.")
