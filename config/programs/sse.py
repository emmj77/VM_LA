# french in code is forbidden
import argparse
import json
import os
import sys
import time

REPLY = "reply"
MODES = ("talk", "ask", "answer")
THINK = "think"


def ts():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


class Flux:
    def __init__(self, turn, path, field):
        self.turn = turn
        self.path = path
        self.field = field
        self.text = []
        self.reasoning_log = []
        self.tools = {}
        self.finish = ""
        self.usage = None
        self.said = ""
        self.evenements = 0
        self._open = False

    def _write(self, obj):
        if not self.path:
            return
        try:
            if not self._open:
                with open(self.path, "w", encoding="utf-8") as f:
                    f.write("")
                self._open = True
            with open(self.path, "a", encoding="utf-8") as f:
                f.write(json.dumps(obj, ensure_ascii=False) + "\n")
        except OSError:
            pass

    def say(self, text, mode=""):
        if not text or text == self.said:
            return
        self.said = text
        self._write({"turn": self.turn, "ts": ts(), "kind": REPLY, "mode": mode or "talk",
                      "text": self.said, "partial": True})

    @staticmethod
    def _strings(args):
        i = (args or "").find('"a"')
        if i < 0:
            return []
        i = args.find("[", i)
        if i < 0:
            return []
        out, i, n = [], i + 1, len(args)
        while i < n:
            ch = args[i]
            if ch in " \t\r\n,":
                i += 1
                continue
            if ch == "]":
                break
            if ch != '"':
                depth, q = 0, False
                while i < n:
                    c2 = args[i]
                    if q:
                        if c2 == "\\":
                            i += 2
                            continue
                        if c2 == '"':
                            q = False
                    elif c2 == '"':
                        q = True
                    elif c2 in "[{":
                        depth += 1
                    elif c2 in "]}":
                        if depth == 0:
                            break
                        depth -= 1
                    elif c2 == "," and depth == 0:
                        break
                    i += 1
                continue
            i += 1
            buf, esc, closed = [], False, False
            while i < n:
                c2 = args[i]
                if esc:
                    buf.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\", "/": "/"}.get(c2, c2))
                    esc = False
                elif c2 == "\\":
                    esc = True
                elif c2 == '"':
                    closed = True
                    i += 1
                    break
                else:
                    buf.append(c2)
                i += 1
            out.append("".join(buf))
            if not closed:
                break
        return out

    @classmethod
    def text_in_arguments(cls, args):
        a = cls._strings(args)
        if len(a) < 3 or a[0] not in MODES:
            return "", ""
        return a[0], a[-1]

    def chunk(self, obj):
        self.evenements += 1
        choice = (obj.get("choices") or [{}])
        c = choice[0] if choice else {}
        d = c.get("delta") or {}
        if obj.get("usage"):
            self.usage = obj["usage"]
        if c.get("finish_reason"):
            self.finish = c["finish_reason"]
        txt = d.get("content")
        if txt:
            self.text.append(txt)
            self.say("".join(self.text))
        reasoning = None
        if self.field:
            reasoning = d.get(self.field)
        else:
            reasoning = d.get("reasoning") or d.get("reasoning_content")
        if reasoning:
            self.reasoning_log.append(reasoning)
            self._write({"turn": self.turn, "ts": ts(), "kind": THINK, "text": reasoning})
        for tc in (d.get("tool_calls") or []):
            i = tc.get("index", 0)
            o = self.tools.setdefault(i, {"id": "", "name": "", "arguments": ""})
            if tc.get("id"):
                o["id"] = tc["id"]
            fn = tc.get("function") or {}
            if fn.get("name"):
                o["name"] += fn["name"]
            if fn.get("arguments"):
                o["arguments"] += fn["arguments"]
            _mode, _said = self.text_in_arguments(o["arguments"])
            self.say(_said, _mode)
            self._write({"turn": self.turn, "ts": ts(), "kind": "tool", "index": i,
                          "name": o["name"], "text": fn.get("arguments") or ""})

    def answer(self):
        tools = []
        for i in sorted(self.tools):
            o = self.tools[i]
            if not o["name"]:
                continue
            tools.append({"index": i, "id": o["id"] or ("call_la_stream_%d_%d" % (self.turn, i)),
                           "type": "function",
                           "function": {"name": o["name"], "arguments": o["arguments"]}})
        msg = {"role": "assistant", "content": "".join(self.text)}
        if self.reasoning_log:
            msg[self.field or "reasoning_content"] = "".join(self.reasoning_log)
        if tools:
            msg["tool_calls"] = tools
        out = {"choices": [{"index": 0, "finish_reason": self.finish or "stop", "message": msg}]}
        if self.usage:
            out["usage"] = self.usage
        return out


def main():
    ap = argparse.ArgumentParser(description="an SSE stream -> one single reply")
    ap.add_argument("--turn", type=int, default=0)
    ap.add_argument("--state", default="", help="the state directory (reply.stream)")
    ap.add_argument("--reason-field", default="")
    a = ap.parse_args()

    path = os.path.join(a.state, "reply.stream") if a.state else ""
    f = Flux(a.turn, path, a.reason_field)
    left = []
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        if not line.startswith("data:"):
            left.append(line)
            continue
        data = line[5:].strip()
        if not data or data == "[DONE]":
            if data == "[DONE]":
                break
            continue
        try:
            f.chunk(json.loads(data))
        except ValueError:
            left.append(data)
    if not f.text and not f.reasoning_log and not f.tools:
        if left:
            reason = " ".join(left)[:400]
        elif f.evenements:
            reason = "the stream carried no text, no reasoning, no tool call"
        else:
            reason = "no event in the body (not an SSE stream)"
        sys.stdout.write(json.dumps({"error": {"message": reason}}))
        return 0
    f._write({"turn": a.turn, "ts": ts(), "kind": "end", "finish": f.finish or "stop"})
    sys.stdout.write(json.dumps(f.answer(), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
