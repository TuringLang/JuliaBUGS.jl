# Internal API

Reference for internal-only symbols inside `JuliaBUGS.Parser`,
`JuliaBUGS.Parser.CompilerUtils`, and `JuliaBUGS.Model`. These are not
part of the public API and may change without notice.

## `JuliaBUGS.Parser`

```@autodocs
Modules = [JuliaBUGS.Parser]
Private = true
Public = true
```

## `JuliaBUGS.Parser.CompilerUtils`

```@autodocs
Modules = [JuliaBUGS.Parser.CompilerUtils]
Private = true
Public = true
```

## `JuliaBUGS.Model`

```@autodocs
Modules = [JuliaBUGS.Model]
Private = true
Public = true
Filter = t -> !any(s -> s === t, [
    JuliaBUGS.Model.BUGSModel,
    JuliaBUGS.Model.condition,
    JuliaBUGS.Model.decondition,
])
```
