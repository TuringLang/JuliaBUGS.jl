# Protocol for Program Evaluation 

During the inference, `varinfo` serves as the runtime environment, housing the current values of variables. 
These values are always stored in their native (possibly constraint) spaces. The `varinfo` object encapsulates 
the program's state at different evaluation points, adhering to a chosen topological order of the 
underlying dependency graph. It's worth noting that multiple topological orders can exist that form an 
equivalence class; any of these orders will yield a consistent final state for `varinfo`. When a variable's 
value is updated, it's imperative to also update the values of all its logical descendants to maintain 
state consistency.

The `transformation` field of `varinfo::SimpleVarInfo` may have slightly different meaning than `DynamicPPL`'s. 
The `transformation` in `JuliaBUGS` indicates the transformation in a static sense, and this is a property of the model.