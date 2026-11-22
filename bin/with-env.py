"""with-env implementation (stdlib only). See skills/env-from-example/SKILL.md."""
import os, re, subprocess, sys, threading


def die(msg, code=2):
    sys.stderr.write("with-env: %s\n" % msg)
    sys.exit(code)


def parse_env(path):
    out = {}
    try:
        f = open(path, encoding="utf-8")
    except OSError:
        die("cannot open env file: %s" % path)
    with f:
        for line in f:
            m = re.match(r"\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$", line)
            if not m:
                continue
            v = m.group(2)
            if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
                v = v[1:-1]
            out[m.group(1)] = v
    return out


def pump(src, dst, secrets):
    for line in iter(lambda: src.readline(), b""):
        for sec in secrets:
            line = line.replace(sec.encode("utf-8"), b"***")
        dst.buffer.write(line)
        dst.buffer.flush()


def run_once(cmd, names, env_vals, slot):
    child = {}
    for n in names:
        key = "%s_%s" % (n, slot) if slot else n
        if key not in env_vals or env_vals[key] == "":
            return None, "missing or empty variable: %s" % key
        child[n] = env_vals[key]
    secrets = sorted({v for v in child.values() if len(v) >= 3}, key=len, reverse=True)
    for a in cmd:
        if any(s in a for s in secrets):
            die("refusing: a loaded value would appear in argv")
    env = dict(os.environ)
    env.update(child)
    p = subprocess.Popen(cmd, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    ts = [threading.Thread(target=pump, args=(p.stdout, sys.stdout, secrets)),
          threading.Thread(target=pump, args=(p.stderr, sys.stderr, secrets))]
    for t in ts:
        t.start()
    for t in ts:
        t.join()
    return p.wait(), None


def main(argv):
    if "--" not in argv:
        die("usage: with-env [--env-file PATH] [--slot N | --try-slots 1,2,3] NAME... -- command args")
    i = argv.index("--")
    opts, cmd = argv[:i], argv[i + 1:]
    if not cmd:
        die("no command given")
    env_file, slot, slots, names = ".env", None, None, []
    j = 0
    while j < len(opts):
        o = opts[j]
        if o in ("--env-file", "--slot", "--try-slots"):
            if j + 1 >= len(opts):
                die("%s needs a value" % o)
            v = opts[j + 1]
            j += 2
            if o == "--env-file":
                env_file = v
            elif o == "--slot":
                slot = v
            else:
                slots = [s for s in v.split(",") if s]
        elif o.startswith("-"):
            die("unknown option: %s" % o)
        else:
            if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", o):
                die("bad variable name: %s" % o)
            names.append(o)
            j += 1
    if not names:
        die("no variable names given")
    if slot and slots:
        die("use --slot or --try-slots, not both")
    env_vals = parse_env(env_file)
    if slots:
        last = 1
        for s in slots:
            rc, err = run_once(cmd, names, env_vals, s)
            if err:
                sys.stderr.write("with-env: slot %s: %s\n" % (s, err))
                continue
            sys.stderr.write("with-env: slot %s exit %d\n" % (s, rc))
            if rc == 0:
                sys.exit(0)
            last = rc
        sys.exit(last)
    rc, err = run_once(cmd, names, env_vals, slot)
    if err:
        die(err)
    sys.exit(rc)


main(sys.argv[1:])
