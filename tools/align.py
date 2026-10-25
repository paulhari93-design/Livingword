"""Match each Tamil paragraph to its English paragraph (for the தமிழ் | English switch).

The translation follows the English closely but paragraphs may be split or joined,
and the paragraph numbers differ. We line them up with a dynamic-programming
alignment (like Gale & Church) using:
  * order (paragraphs never cross),
  * length (a long English paragraph becomes a long Tamil one),
  * numbers that appear in both (years, verses, counts),
  * paragraph numbers, when both texts use the same numbering.

Returns: for every Tamil paragraph, the index of the matching English paragraph.
"""
import math
import re

_LEAD = re.compile(r"^\s*(\d{1,3})(?:\.|\s)")
_NUM = re.compile(r"\d+")


def _length(t):
    return max(1, len(re.sub(r"\s+", "", t)))


def _numbers(t):
    return frozenset(_NUM.findall(_LEAD.sub("", t, count=1)))


def _lead(t):
    m = _LEAD.match(t)
    return int(m.group(1)) if m else None


def align(ta, en):
    n, m = len(ta), len(en)
    if n == 0 or m == 0:
        return [0] * n
    a = [_length(x) for x in ta]
    b = [_length(x) for x in en]
    ratio = sum(a) / sum(b)
    na = [_numbers(x) for x in ta]
    nb = [_numbers(x) for x in en]
    la = [_lead(x) for x in ta]
    lb = [_lead(x) for x in en]
    # Use paragraph numbers only when both texts number the same way.
    max_a = max([x for x in la if x] or [0])
    max_b = max([x for x in lb if x] or [0])
    same_numbering = max_a and max_b and abs(max_a - max_b) <= max(3, 0.1 * max_b)

    pa = [0]
    for x in a:
        pa.append(pa[-1] + x)
    pb = [0]
    for x in b:
        pb.append(pb[-1] + x)

    band = max(25, int(0.25 * max(n, m)))  # stay near the diagonal (faster)
    inf = float("inf")
    cost = {(0, 0): 0.0}
    back = {}
    moves = ((1, 1, 0.0), (1, 0, 6.0), (0, 1, 6.0), (2, 1, 1.5), (1, 2, 1.5), (3, 1, 3.0), (1, 3, 3.0))
    for i in range(n + 1):
        jc = i * m / n
        for j in range(max(0, int(jc) - band), min(m, int(jc) + band) + 1):
            c0 = cost.get((i, j))
            if c0 is None:
                continue
            for di, dj, pen in moves:
                ii, jj = i + di, j + dj
                if ii > n or jj > m:
                    continue
                if di == 0 or dj == 0:
                    c = pen
                else:
                    lta = pa[ii] - pa[i]
                    len_ = pb[jj] - pb[j]
                    c = abs(math.log((lta + 20) / (ratio * len_ + 20))) * 4 + pen
                    sa = frozenset().union(*na[i:ii])
                    sb = frozenset().union(*nb[j:jj])
                    if sa and sb:
                        c -= 1.5 * len(sa & sb) / len(sa | sb)
                    if same_numbering and la[i] is not None and lb[j] is not None:
                        c += -4.0 if la[i] == lb[j] else 2.0
                v = c0 + c
                if v < cost.get((ii, jj), inf):
                    cost[(ii, jj)] = v
                    back[(ii, jj)] = (i, j)

    if (n, m) not in back:  # should not happen; fall back to proportional
        return [min(m - 1, int(i * m / n)) for i in range(n)]
    result = [0] * n
    i, j = n, m
    while (i, j) != (0, 0):
        pi, pj = back[(i, j)]
        for k in range(pi, i):
            result[k] = min(pj, m - 1)
        i, j = pi, pj
    return result
