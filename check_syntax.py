import re

def check_luau_syntax(filename):
    with open(filename, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    open_blocks = 0
    in_block_comment = False
    in_multiline_string = False

    block_openers = re.compile(r'\b(then|do|function|repeat)\b')
    block_closers = re.compile(r'\b(end|until)\b')

    for i, line in enumerate(lines, 1):
        s = line.strip()
        # strip comments
        if '--[[' in s:
            in_block_comment = True
        if in_block_comment:
            if ']]' in s:
                in_block_comment = False
            continue
        if s.startswith('--'):
            continue
        # simple check for unbalanced blocks
        clean_s = re.sub(r'".*?"', '', s)
        clean_s = re.sub(r"'.*?'", '', clean_s)
        clean_s = re.sub(r'--.*$', '', clean_s)

        opens = len(block_openers.findall(clean_s))
        closes = len(block_closers.findall(clean_s))
        open_blocks += opens - closes

    print(f"{filename}: block balance = {open_blocks} (Lines: {len(lines)})")

for f in ["GameplayConfig.luau", "PlayerData.server.luau", "GameplayManager.server.luau", "StatsHUDController.client.luau"]:
    check_luau_syntax(f)
