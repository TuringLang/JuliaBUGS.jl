struct Trace
    values
    logp
end

# 

# for now, we are not placing bijectors here
# the bijiector for node function can be an advanced thing, because:
# 1. if we are talking about VI, the transformation for node function need some work
# 2. because the function is still open, for different input, the returned distribution can be different

# x[1] <- a * x[2]
# node function: function x_[1](x_[2], a) return a * x_[2] end
# value function:
# function x_[1](trace, x_[2], a)
#     x_[2] = get(trace, x_[2])
#     a = get(trace, a)
#     x_[1] = node_function(x_[2], a)
#     set(trace, x_[1], x_[1])
# end

