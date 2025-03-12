## MWM (make was a mistake)
Just to be clear, I respect the people who made make.
It's still the first tool I reach for when I start small projects.
Additionally, TCL was made after make, which means it was not avaliable for this task at the time.

### Motivation
I realized that if you use a dynamic, scripting language, you do not need to use a DSL for make-like jobs.
You can use the implementation language to define targets and simply "source" the file to get tasks.
That should be much simpler to implement than make.
Granted, you're relying on the complexity of the scripting language, but IMO, TCL's syntax is simpler than make's syntax anyway.
