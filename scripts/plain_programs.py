"""Complete, small programs for the ten foundation topics without graded labs."""
from textwrap import indent
import re

BODY = {
'values': {
'c':'int quantity = 3, price = 199;\nprintf("%d\\n", quantity * price);',
'cpp':'int quantity = 3, price = 199;\nstd::cout << quantity * price << "\\n";',
'csharp':'int quantity = 3, price = 199;\nConsole.WriteLine(quantity * price);',
'java':'int quantity = 3, price = 199;\nSystem.out.println(quantity * price);',
'python':'quantity = 3\nprice = 199\nprint(quantity * price)',
'javascript':'const quantity = 3;\nconst price = 199;\nconsole.log(quantity * price);',
'go':'quantity, price := 3, 199\nfmt.Println(quantity * price)',
},
'input': {
'c':'char name[80];\nif (!fgets(name, sizeof name, stdin)) return 1;\nname[strcspn(name, "\\r\\n")] = 0;\nint age;\nif (scanf("%d", &age) != 1) return 1;\nprintf("%s %d\\n", name, age);',
'cpp':'std::string name;\nint age;\nif (!std::getline(std::cin, name) || !(std::cin >> age)) return 1;\nstd::cout << name << " " << age << "\\n";',
'csharp':'string name = Console.ReadLine() ?? "";\nint age = int.Parse(Console.ReadLine() ?? "");\nConsole.WriteLine($"{name} {age}");',
'java':'var input = new Scanner(System.in);\nString name = input.nextLine();\nint age = Integer.parseInt(input.nextLine());\nSystem.out.println(name + " " + age);',
'python':'name = input()\nage = int(input())\nprint(name, age)',
'javascript':'const lines = require("node:fs").readFileSync(0, "utf8").split(/\\r?\\n/);\nconst name = lines[0];\nconst age = Number(lines[1]);\nconsole.log(name + " " + age);',
'go':'input := bufio.NewScanner(os.Stdin)\nif !input.Scan() { return }\nname := input.Text()\nif !input.Scan() { return }\nage, err := strconv.Atoi(input.Text())\nif err != nil { return }\nfmt.Printf("%s %d\\n", name, age)',
},
'scope': {
'c':'printf("%d\\n", cost(7, 3));\nprintf("%d\\n", cost(2, 4));',
'cpp':'std::cout << cost(7, 3) << "\\n" << cost(2, 4) << "\\n";',
'csharp':'Console.WriteLine(Cost(7, 3));\nConsole.WriteLine(Cost(2, 4));',
'java':'System.out.println(cost(7, 3));\nSystem.out.println(cost(2, 4));',
'python':'print(cost(7, 3))\nprint(cost(2, 4))',
'javascript':'console.log(cost(7, 3));\nconsole.log(cost(2, 4));',
'go':'fmt.Println(cost(7, 3))\nfmt.Println(cost(2, 4))',
},
'collections': {
'c':'int counts[10] = {0};\nint digits[] = {3, 7, 3};\nfor (int i = 0; i < 3; i++) counts[digits[i]]++;\nprintf("%d\\n", counts[3]);',
'cpp':'std::map<int, int> counts;\nfor (int digit : {3, 7, 3}) counts[digit]++;\nstd::cout << counts[3] << "\\n";',
'csharp':'var counts = new Dictionary<int, int>();\nforeach (int digit in new[] {3, 7, 3}) counts[digit] = counts.GetValueOrDefault(digit) + 1;\nConsole.WriteLine(counts[3]);',
'java':'var counts = new HashMap<Integer, Integer>();\nfor (int digit : new int[] {3, 7, 3}) counts.put(digit, counts.getOrDefault(digit, 0) + 1);\nSystem.out.println(counts.get(3));',
'python':'counts = {}\nfor digit in [3, 7, 3]:\n    counts[digit] = counts.get(digit, 0) + 1\nprint(counts[3])',
'javascript':'const counts = new Map();\nfor (const digit of [3, 7, 3]) counts.set(digit, (counts.get(digit) ?? 0) + 1);\nconsole.log(counts.get(3));',
'go':'counts := make(map[int]int)\nfor _, digit := range []int{3, 7, 3} { counts[digit]++ }\nfmt.Println(counts[3])',
},
'records': {
'c':'struct Product product = {1, "Cat", 3};\nprintf("%s %d\\n", product.title, product.stock);',
'cpp':'Product product{1, "Cat", 3};\nstd::cout << product.title << " " << product.stock << "\\n";',
'csharp':'var product = new Product(1, "Cat", 3);\nConsole.WriteLine($"{product.Title} {product.Stock}");',
'java':'var product = new Product(1, "Cat", 3);\nSystem.out.println(product.title() + " " + product.stock());',
'python':'product = {"id": 1, "title": "Cat", "stock": 3}\nprint(product["title"], product["stock"])',
'javascript':'const product = {id: 1, title: "Cat", stock: 3};\nconsole.log(product.title + " " + product.stock);',
'go':'product := Product{ID: 1, Title: "Cat", Stock: 3}\nfmt.Println(product.Title, product.Stock)',
},
'errors': {
'c':'char text[80];\nif (!fgets(text, sizeof text, stdin)) return 1;\nchar *end;\nerrno = 0;\nlong age = strtol(text, &end, 10);\nif (end == text || errno == ERANGE || (*end != 0 && *end != \'\\n\' && *end != \'\\r\')) {\n    puts("Нужно целое число");\n    return 0;\n}\nprintf("%ld\\n", age);',
'cpp':'std::string text;\nstd::getline(std::cin, text);\ntry {\n    std::size_t end;\n    int age = std::stoi(text, &end);\n    if (end != text.size()) throw std::invalid_argument("input");\n    std::cout << age << "\\n";\n} catch (const std::exception&) { std::cout << "Нужно целое число\\n"; }',
'csharp':'if (int.TryParse(Console.ReadLine(), out int age)) Console.WriteLine(age);\nelse Console.WriteLine("Нужно целое число");',
'java':'String text = new Scanner(System.in).nextLine();\ntry { System.out.println(Integer.parseInt(text)); }\ncatch (NumberFormatException error) { System.out.println("Нужно целое число"); }',
'python':'try:\n    age = int(input())\n    print(age)\nexcept ValueError:\n    print("Нужно целое число")',
'javascript':'const text = require("node:fs").readFileSync(0, "utf8").trim();\nconst age = Number(text);\nif (text !== "" && Number.isInteger(age)) console.log(age);\nelse console.log("Нужно целое число");',
'go':'data, err := io.ReadAll(os.Stdin)\nif err != nil { return }\nage, err := strconv.Atoi(strings.TrimSpace(string(data)))\nif err != nil { fmt.Println("Нужно целое число"); return }\nfmt.Println(age)',
},
'files': {
'c':'FILE *file = fopen("notes.txt", "w");\nif (!file) return 1;\nint written = fputs("Cat", file);\nint closed = fclose(file);\nif (written < 0 || closed != 0) return 1;\nfile = fopen("notes.txt", "r");\nif (!file) return 1;\nchar text[20];\nif (!fgets(text, sizeof text, file)) { fclose(file); return 1; }\nif (fclose(file) != 0) return 1;\nputs(text);',
'cpp':'{ std::ofstream file("notes.txt");\n  if (!file) return 1;\n  file << "Cat";\n  file.close();\n  if (!file) return 1; }\nstd::ifstream file("notes.txt");\nstd::string text;\nif (!std::getline(file, text)) return 1;\nstd::cout << text << "\\n";',
'csharp':'File.WriteAllText("notes.txt", "Cat");\nConsole.WriteLine(File.ReadAllText("notes.txt"));',
'java':'var path = Path.of("notes.txt");\nFiles.writeString(path, "Cat");\nSystem.out.println(Files.readString(path));',
'python':'from pathlib import Path\npath = Path("notes.txt")\npath.write_text("Cat", encoding="utf-8")\nprint(path.read_text(encoding="utf-8"))',
'javascript':'const fs = require("node:fs");\nfs.writeFileSync("notes.txt", "Cat", "utf8");\nconsole.log(fs.readFileSync("notes.txt", "utf8"));',
'go':'if err := os.WriteFile("notes.txt", []byte("Cat"), 0600); err != nil { return }\ndata, err := os.ReadFile("notes.txt")\nif err != nil { return }\nfmt.Println(string(data))',
},
'json': {
'c':'int version = 1;\nprintf("{\\"version\\":%d,\\"notes\\":[]}\\n", version);',
'cpp':'int version = 1;\nstd::cout << "{\\"version\\":" << version << ",\\"notes\\":[]}\\n";',
'csharp':'string text = System.Text.Json.JsonSerializer.Serialize(new {version = 1, notes = Array.Empty<string>()});\nusing var data = System.Text.Json.JsonDocument.Parse(text);\nConsole.WriteLine(data.RootElement.GetProperty("version").GetInt32());',
'java':'int version = 1;\nSystem.out.println("{\\"version\\":" + version + ",\\"notes\\":[]}");',
'python':'import json\ntext = json.dumps({"version": 1, "notes": []})\ndata = json.loads(text)\nprint(data["version"])',
'javascript':'const text = JSON.stringify({version: 1, notes: []});\nconst data = JSON.parse(text);\nconsole.log(data.version);',
'go':'data, err := json.Marshal(struct { Version int `json:"version"`; Notes []string `json:"notes"` }{1, []string{}})\nif err != nil { return }\nvar result struct { Version int `json:"version"` }\nif err := json.Unmarshal(data, &result); err != nil { return }\nfmt.Println(result.Version)',
},
'modules': {
'c':'printf("%d\\n", add(2, 3));',
'cpp':'std::cout << add(2, 3) << "\\n";',
'csharp':'Console.WriteLine(Add(2, 3));',
'java':'System.out.println(add(2, 3));',
'python':'print(add(2, 3))',
'javascript':'console.log(add(2, 3));',
'go':'fmt.Println(add(2, 3))',
},
'complexity': {
'c':'int values[] = {1, 2, 1, 3};\nfor (int i = 0; i < 4; i++)\n    for (int j = i + 1; j < 4; j++)\n        if (values[i] == values[j]) printf("%d\\n", values[i]);',
'cpp':'std::set<int> seen;\nfor (int value : {1, 2, 1, 3})\n    if (!seen.insert(value).second) std::cout << value << "\\n";',
'csharp':'var seen = new HashSet<int>();\nforeach (int value in new[] {1, 2, 1, 3})\n    if (!seen.Add(value)) Console.WriteLine(value);',
'java':'var seen = new HashSet<Integer>();\nfor (int value : new int[] {1, 2, 1, 3})\n    if (!seen.add(value)) System.out.println(value);',
'python':'seen = set()\nfor value in [1, 2, 1, 3]:\n    if value in seen:\n        print(value)\n    seen.add(value)',
'javascript':'const seen = new Set();\nfor (const value of [1, 2, 1, 3]) {\n    if (seen.has(value)) console.log(value);\n    seen.add(value);\n}',
'go':'seen := make(map[int]bool)\nfor _, value := range []int{1, 2, 1, 3} {\n    if seen[value] { fmt.Println(value) }\n    seen[value] = true\n}',
},
}


def program(lang, topic):
    body=BODY[topic][lang];helper=''
    if topic in ('scope','modules'):
        name='cost' if topic=='scope' else 'add';operation='a * b' if topic=='scope' else 'a + b'
        helper={
            'c':f'int {name}(int a, int b) {{ return {operation}; }}',
            'cpp':f'int {name}(int a, int b) {{ return {operation}; }}',
            'csharp':f'static int {name.title()}(int a, int b) {{ return {operation}; }}',
            'java':f'static int {name}(int a, int b) {{ return {operation}; }}',
            'python':f'def {name}(a, b):\n    return {operation}',
            'javascript':f'function {name}(a, b) {{ return {operation}; }}',
            'go':f'func {name}(a, b int) int {{ return {operation} }}',
        }[lang]
        if topic == 'scope':
            helper = {
                'c':'int cost(int price, int quantity) { int total = price * quantity; return total; }',
                'cpp':'int cost(int price, int quantity) { int total = price * quantity; return total; }',
                'csharp':'static int Cost(int price, int quantity) { int total = price * quantity; return total; }',
                'java':'static int cost(int price, int quantity) { int total = price * quantity; return total; }',
                'python':'def cost(price, quantity):\n    total = price * quantity\n    return total',
                'javascript':'function cost(price, quantity) { const total = price * quantity; return total; }',
                'go':'func cost(price, quantity int) int { total := price * quantity; return total }',
            }[lang]
    if topic=='records':
        helper={
            'c':'struct Product { int id; const char *title; int stock; };',
            'cpp':'struct Product { int id; std::string title; int stock; };',
            'csharp':'public record Product(int Id, string Title, int Stock);',
            'java':'record Product(int id, String title, int stock) {}',
            'python':'',
            'javascript':'',
            'go':'type Product struct { ID int; Title string; Stock int }',
        }[lang]
    if lang in ('python','javascript'):code=helper+'\n\n'+body+'\n'
    elif lang=='c':code='#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <errno.h>\n\n'+helper+'\n\nint main(void) {\n'+indent(body,'    ')+'\n    return 0;\n}\n'
    elif lang=='cpp':code='#include <iostream>\n#include <string>\n#include <map>\n#include <set>\n#include <fstream>\n#include <stdexcept>\n\n'+helper+'\n\nint main() {\n'+indent(body,'    ')+'\n}\n'
    elif lang=='csharp':code='using System;\nusing System.IO;\nusing System.Collections.Generic;\n\nclass Program {\n'+indent(helper,'    ')+'\n    static void Main() {\n'+indent(body,'        ')+'\n    }\n}\n'
    elif lang=='java':code='import java.util.*;\nimport java.nio.file.*;\n\npublic class Main {\n'+indent(helper,'    ')+'\n    public static void main(String[] args) throws Exception {\n'+indent(body,'        ')+'\n    }\n}\n'
    else:
        libraries={'fmt':'fmt','os':'os','bufio':'bufio','strconv':'strconv','strings':'strings','io':'io','json':'encoding/json'}
        imports=[path for alias,path in libraries.items() if re.search(r'\b'+re.escape(alias)+r'\.', body+helper)]
        code='package main\n\nimport (\n'+''.join('    "'+x+'"\n' for x in imports)+')\n\n'+helper+'\n\nfunc main() {\n'+indent(body,'    ')+'\n}\n'
    output={'values':'597','input':'Cat 20','scope':'21\n8','collections':'2','records':'Cat 3',
            'errors':'12','files':'Cat','json':'1','modules':'5','complexity':'1'}[topic]
    if topic=='json' and lang in ('c','cpp','java'):output='{"version":1,"notes":[]}'
    data='Cat\n20\n' if topic=='input' else '12\n' if topic=='errors' else ''
    tests=[dict(input=data,expected=output)]
    if topic=='errors':tests.append(dict(input='cat\n',expected='Нужно целое число'))
    return dict(code=code.lstrip(),tests=tests)
