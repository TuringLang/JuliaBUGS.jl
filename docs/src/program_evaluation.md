# Evaluation of `BUGSModel`  

During model evaluation, `varinfo` serves as the runtime environment, housing the current values of variables.
These values are always stored in their native (possibly constraint) spaces.
The `varinfo` represents the state of program evaluation at different evaluation points, given a chosen order of node evaluation.
By default, the order is chosen to be a particular topological order of the nodes in the graph.
It's worth noting that multiple topological orders can exist that form an equivalence class; any of these orders will yield a consistent final state for `varinfo`.
When a variable's value is updated, it's imperative to also update the values of all its logical descendants to maintain state consistency.

Note this may be different from `DynamicPPL`, where the `varinfo` will store the transformed values of variables if transformations are used.
