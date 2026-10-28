"""Complete standard-library-only programs for eight worked algorithm lectures.
C-like languages share an explicit integer algorithm, not translated prose.
Python implementations are separate. Examples are executed in validation.
"""
import re

C_BODIES = [
'''ARRAY(prefix, n + 1, 0)
for (int i = 0; i < n; i++) {
    prefix[i + 1] = prefix[i] + a[i];
}
for (int q = 0; q < k; q++) {
    int left = a[n + 2 * q];
    int right = a[n + 2 * q + 1];
    PRINT(prefix[right] - prefix[left]);
}''',
'''int left = 0;
int total = 0;
int best = 0;
for (int right = 0; right < n; right++) {
    total += a[right];
    while (left <= right && total > k) {
        total -= a[left];
        left++;
    }
    best = max(best, right - left + 1);
}
PRINT(best);''',
'''int ending = a[0];
int best = a[0];
for (int i = 1; i < n; i++) {
    ending = max(a[i], ending + a[i]);
    best = max(best, ending);
}
PRINT(best);''',
'''int low = 0;
int high = 0;
for (int i = 0; i < n; i++) {
    low = max(low, a[i]);
    high += a[i];
}
while (low < high) {
    int middle = low + (high - low) / 2;
    int groups = 1;
    int load = 0;
    for (int i = 0; i < n; i++) {
        if (load + a[i] > middle) {
            groups++;
            load = 0;
        }
        load += a[i];
    }
    if (groups <= k) {
        high = middle;
    } else {
        low = middle + 1;
    }
}
PRINT(low);''',
'''ARRAY(dp, k + 1, 1000000)
dp[0] = 0;
for (int amount = 1; amount <= k; amount++) {
    for (int i = 0; i < n; i++) {
        if (a[i] <= amount) {
            dp[amount] = min(dp[amount], dp[amount - a[i]] + 1);
        }
    }
}
int answer = dp[k];
if (answer >= 1000000) {
    answer = -1;
}
PRINT(answer);''',
'''ARRAY(dp, n, 1)
int answer = 0;
for (int i = 0; i < n; i++) {
    for (int j = 0; j < i; j++) {
        if (a[j] < a[i]) {
            dp[i] = max(dp[i], dp[j] + 1);
        }
    }
    answer = max(answer, dp[i]);
}
PRINT(answer);''',
'''ARRAY(distance, n, -1)
ARRAY(queue, n, 0)
int head = 0;
int tail = 0;
distance[k] = 0;
queue[tail] = k;
tail++;
while (head < tail) {
    int vertex = queue[head];
    head++;
    for (int next = 0; next < n; next++) {
        if (a[vertex * n + next] != 0 && distance[next] == -1) {
            distance[next] = distance[vertex] + 1;
            queue[tail] = next;
            tail++;
        }
    }
}
for (int i = 0; i < n; i++) {
    PRINT(distance[i]);
}''',
'''ARRAY(distance, n, 1000000000)
ARRAY(used, n, 0)
distance[k] = 0;
for (int step = 0; step < n; step++) {
    int vertex = -1;
    for (int i = 0; i < n; i++) {
        if (used[i] == 0) {
            if (vertex == -1 || distance[i] < distance[vertex]) {
                vertex = i;
            }
        }
    }
    if (vertex == -1 || distance[vertex] == 1000000000) {
        break;
    }
    used[vertex] = 1;
    for (int next = 0; next < n; next++) {
        int weight = a[vertex * n + next];
        if (weight >= 0 && used[next] == 0) {
            distance[next] = min(distance[next], distance[vertex] + weight);
        }
    }
}
for (int i = 0; i < n; i++) {
    int value = distance[i];
    if (value == 1000000000) {
        value = -1;
    }
    PRINT(value);
}''',
]

PYTHON_BODIES = [
'''prefix = [0]
for value in a[:n]:
    prefix.append(prefix[-1] + value)
for q in range(k):
    left, right = a[n + 2*q:n + 2*q + 2]
    print(prefix[right] - prefix[left])''',
'''left = total = best = 0
for right, value in enumerate(a):
    total += value
    while left <= right and total > k:
        total -= a[left]
        left += 1
    best = max(best, right - left + 1)
print(best)''',
'''ending = best = a[0]
for value in a[1:]:
    ending = max(value, ending + value)
    best = max(best, ending)
print(best)''',
'''low, high = max(a), sum(a)
while low < high:
    middle = low + (high - low) // 2
    groups, load = 1, 0
    for value in a:
        if load + value > middle:
            groups += 1
            load = 0
        load += value
    if groups <= k:
        high = middle
    else:
        low = middle + 1
print(low)''',
'''dp = [10**6] * (k + 1)
dp[0] = 0
for amount in range(1, k + 1):
    for coin in a:
        if coin <= amount:
            dp[amount] = min(dp[amount], dp[amount - coin] + 1)
print(-1 if dp[k] >= 10**6 else dp[k])''',
'''dp = [1] * n
for i in range(n):
    for j in range(i):
        if a[j] < a[i]:
            dp[i] = max(dp[i], dp[j] + 1)
print(max(dp, default=0))''',
'''distance = [-1] * n
queue = [k]
distance[k] = 0
head = 0
while head < len(queue):
    vertex = queue[head]
    head += 1
    for nxt in range(n):
        if a[vertex*n + nxt] != 0 and distance[nxt] == -1:
            distance[nxt] = distance[vertex] + 1
            queue.append(nxt)
print(*distance, sep="\\n")''',
'''infinity = 10**9
distance = [infinity] * n
used = [False] * n
distance[k] = 0
for _ in range(n):
    candidates = [i for i in range(n) if not used[i]]
    if not candidates:
        break
    vertex = min(candidates, key=lambda i: distance[i])
    if distance[vertex] == infinity:
        break
    used[vertex] = True
    for nxt in range(n):
        weight = a[vertex*n + nxt]
        if weight >= 0 and not used[nxt]:
            distance[nxt] = min(distance[nxt], distance[vertex] + weight)
print(*[-1 if value == infinity else value for value in distance], sep="\\n")''',
]


def program(language, index):
    if language == 'python':
        return 'import sys\n\nvalues = list(map(int, sys.stdin.read().split()))\nn, k = values[:2]\na = values[2:]\n\n' + PYTHON_BODIES[index] + '\n'
    body = C_BODIES[index]
    arrays = []
    def array(match):
        name, length, initial = match.groups(); arrays.append(name)
        if language == 'c':
            return f'int *{name} = malloc((({length}) > 0 ? ({length}) : 1) * sizeof *{name});\nif ({name} == NULL) {{ return 1; }}\nfor (int fill = 0; fill < {length}; fill++) {{ {name}[fill] = {initial}; }}'
        if language == 'cpp': return f'std::vector<int> {name}({length}, {initial});'
        if language == 'java': return f'int[] {name} = new int[{length}];\nArrays.fill({name}, {initial});'
        if language == 'csharp': return f'int[] {name} = new int[{length}];\nArray.Fill({name}, {initial});'
        if language == 'javascript': return f'let {name} = Array({length}).fill({initial});'
        if language == 'go': return f'{name} := make([]int, {length});\nfor fill := range {name} {{ {name}[fill] = {initial}; }}'
        raise ValueError(language)
    body = re.sub(r'ARRAY\((\w+), (.*), (-?\d+)\)', array, body)
    if language == 'c':
        body=re.sub(r'PRINT\((.*?)\);',r'printf("%d\\n", \1);',body)
        prefix='#include <stdio.h>\n#include <stdlib.h>\n\nstatic int min(int a, int b) { return a < b ? a : b; }\nstatic int max(int a, int b) { return a > b ? a : b; }\n\nint main(void) {\n    int n, k;\n    if (scanf("%d %d", &n, &k) != 2) { return 1; }\n    int a[20000];\n    int count = 0;\n    while (count < 20000 && scanf("%d", &a[count]) == 1) { count++; }\n'
        suffix=''.join(f'    free({name});\n' for name in arrays)+'    return 0;\n}\n'
    elif language == 'cpp':
        body=body.replace('max(', 'std::max(').replace('min(', 'std::min(')
        body=re.sub(r'PRINT\((.*?)\);',r'std::cout << \1 << "\\n";',body)
        prefix='#include <algorithm>\n#include <iostream>\n#include <vector>\n\nint main() {\n    int n, k;\n    if (!(std::cin >> n >> k)) { return 1; }\n    std::vector<int> a;\n    int value;\n    while (std::cin >> value) { a.push_back(value); }\n'
        suffix='    return 0;\n}\n'
    elif language == 'csharp':
        body=body.replace('max(', 'Math.Max(').replace('min(', 'Math.Min(')
        body=re.sub(r'PRINT\((.*?)\);',r'Console.WriteLine(\1);',body)
        prefix='using System;\n\nstring[] tokens = Console.In.ReadToEnd().Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);\nint[] values = Array.ConvertAll(tokens, int.Parse);\nint n = values[0];\nint k = values[1];\nint[] a = new int[values.Length - 2];\nArray.Copy(values, 2, a, 0, a.Length);\n\n'
        suffix=''
    elif language == 'java':
        body=body.replace('max(', 'Math.max(').replace('min(', 'Math.min(')
        body=re.sub(r'PRINT\((.*?)\);',r'System.out.println(\1);',body)
        prefix='import java.util.*;\n\npublic class Main {\n    public static void main(String[] args) {\n        Scanner scanner = new Scanner(System.in);\n        int n = scanner.nextInt();\n        int k = scanner.nextInt();\n        ArrayList<Integer> input = new ArrayList<>();\n        while (scanner.hasNextInt()) { input.add(scanner.nextInt()); }\n        int[] a = input.stream().mapToInt(Integer::intValue).toArray();\n'
        suffix='    }\n}\n'
    elif language == 'javascript':
        body=re.sub(r'\bint (?=\w)', 'let ', body)
        body=body.replace('max(', 'Math.max(').replace('min(', 'Math.min(')
        body=body.replace('!=','!==').replace(' == ',' === ')
        # Integer division in capacity search is deliberate.
        body=body.replace('low + (high - low) / 2', 'low + Math.floor((high - low) / 2)')
        body=re.sub(r'PRINT\((.*?)\);',r'console.log(\1);',body)
        prefix='const fs = require("node:fs");\nconst values = fs.readFileSync(0, "utf8").trim().split(/\\s+/).map(Number);\nconst [n, k] = values;\nconst a = values.slice(2);\n\n'
        suffix=''
    elif language == 'go':
        body=re.sub(r'for \(int (\w+) = ([^;]+); ([^;]+); ([^)]+)\)',r'for \1 := \2; \3; \4',body)
        body=re.sub(r'\bint (\w+) = ([^;]+);',r'\1 := \2;',body)
        body=re.sub(r'while \(([^\n]+)\)',r'for (\1)',body)
        body=re.sub(r'PRINT\((.*?)\);',r'fmt.Fprintln(out, \1);',body)
        prefix='package main\n\nimport (\n    "bufio"\n    "fmt"\n    "os"\n)\n\nfunc main() {\n    in := bufio.NewReader(os.Stdin)\n    out := bufio.NewWriter(os.Stdout)\n    defer out.Flush()\n    var n, k int\n    if _, err := fmt.Fscan(in, &n, &k); err != nil { return }\n    a := []int{}\n    for {\n        var value int\n        if _, err := fmt.Fscan(in, &value); err != nil { break }\n        a = append(a, value)\n    }\n    _ = k\n'
        suffix='}\n'
    else: raise ValueError(language)
    indent='        ' if language=='java' else '' if language in ['javascript','csharp'] else '    '
    return prefix+'\n'.join(indent+line for line in body.splitlines())+'\n'+suffix
