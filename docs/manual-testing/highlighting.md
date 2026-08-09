# Syntax highlighting manual test

Exercises issue #4: language-specific highlighting, the header bar, and the
Copy button, across several languages and a few edge cases.

## Swift

```swift
import Foundation

struct Greeter {
    let name: String

    func greet() -> String {
        "Hello, \(name)! (\(Date()))"
    }
}

let names = ["Ada", "Grace", "Margaret"]
for name in names where !name.isEmpty {
    print(Greeter(name: name).greet())
}
```

## Python

```python
from dataclasses import dataclass

@dataclass
class Greeter:
    name: str

    def greet(self) -> str:
        return f"Hello, {self.name}!"

if __name__ == "__main__":
    for name in ["Ada", "Grace", "Margaret"]:
        print(Greeter(name).greet())
```

## JavaScript / TypeScript

```javascript
class Greeter {
  constructor(name) {
    this.name = name;
  }

  greet() {
    return `Hello, ${this.name}!`;
  }
}

const names = ["Ada", "Grace", "Margaret"];
names.forEach((n) => console.log(new Greeter(n).greet()));
```

```typescript
interface Named {
  name: string;
}

function greet({ name }: Named): string {
  return `Hello, ${name}!`;
}
```

## Rust

```rust
struct Greeter {
    name: String,
}

impl Greeter {
    fn greet(&self) -> String {
        format!("Hello, {}!", self.name)
    }
}

fn main() {
    let names = vec!["Ada", "Grace", "Margaret"];
    for name in names {
        let g = Greeter { name: name.to_string() };
        println!("{}", g.greet());
    }
}
```

## Go

```go
package main

import "fmt"

type Greeter struct {
	Name string
}

func (g Greeter) Greet() string {
	return fmt.Sprintf("Hello, %s!", g.Name)
}

func main() {
	for _, name := range []string{"Ada", "Grace", "Margaret"} {
		fmt.Println(Greeter{Name: name}.Greet())
	}
}
```

## SQL

```sql
SELECT u.id, u.name, COUNT(o.id) AS order_count
FROM users u
LEFT JOIN orders o ON o.user_id = u.id
WHERE u.created_at > '2026-01-01'
GROUP BY u.id, u.name
ORDER BY order_count DESC
LIMIT 10;
```

## JSON

```json
{
  "name": "Folium",
  "version": "0.1.0",
  "languages": ["swift", "python", "rust", "go"],
  "highlighted": true
}
```

## Bash / shell

```bash
#!/usr/bin/env bash
set -euo pipefail

for file in *.md; do
  echo "Rendering: $file"
  folium "$file" || echo "failed: $file" >&2
done
```

## YAML

```yaml
name: CI
on: [push, pull_request]
jobs:
  test:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - run: make check
```

## Diff

```diff
- func greet(name: String) -> String {
-     "Hi, \(name)"
- }
+ func greet(name: String) -> String {
+     "Hello, \(name)!"
+ }
```

## Unlabeled fence (no language — should still get chrome + Copy, best-effort highlighting)

```
plain text, no declared language
just make sure this still renders with the header bar and copy button
```

## Inline code (should NOT get the block chrome)

Use `let x = CodeBlockDecorator.decorate(body)` to wrap fenced blocks; inline
spans like `--accentFg` or `npm install` should render as plain inline code,
with no header bar or Copy button.

## Nested in a blockquote

> Blockquoted code still needs its own header bar and Copy button:
>
> ```python
> def nested():
>     return "still works inside a blockquote"
> ```

## Nested in a list item

1. First, install dependencies:
   ```bash
   brew install swiftlint
   ```
2. Then run the checks:
   ```bash
   make check
   ```

## Escaping edge case

A block containing characters that must stay HTML-escaped (`<`, `>`, `&`,
and a literal closing tag as text) so the Copy button copies the *raw*
source, not escaped entities:

```html
<div class="example">
  <!-- </code></pre> as literal text, not real markup -->
  <p>1 &lt; 2 &amp;&amp; 3 &gt; 2</p>
</div>
```

## Long line (tests horizontal scroll inside the block, not page-wide)

```python
result = some_function(argument_one, argument_two, argument_three, argument_four, argument_five, argument_six, argument_seven)
```
