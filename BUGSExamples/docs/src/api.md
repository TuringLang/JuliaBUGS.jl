# API Reference

```@meta
CurrentModule = BUGSExamples
```

## Types

```@docs
BUGSExample
```

## Functions

```@docs
BUGSExamples.list
BUGSExamples.examples
```

## Module

```@docs
BUGSExamples.BUGSExamples
```

## Internal

```@autodocs
Modules = [BUGSExamples]
Filter = t -> !any(n -> n === t, [BUGSExample, BUGSExamples.list, BUGSExamples.examples, BUGSExamples])
```
