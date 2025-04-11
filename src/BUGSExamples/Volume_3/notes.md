1. Camel has partially observed two dimensional Gaussian random variables. In general, this doesn't work, but in case of Gaussian, the analytical form is available
2. discrete r.v. `S`
3. `dloglike`
4. several shapes, work
5. works
6. only deterministic computation
7. has loops in coarse graph; step dependency with `var"pi"[k, t, s] = inprod(y[k, t - 1, :], Lambda[k, t, :, s])` and `y[k, t, 1:S] ~ dmulti(var"pi"[k, t, :], 1)`
8. self loop: `pi[k, t, s] = inprod(pi[k, t - 1, :], Lambda[k, t, :, s])`
9. self loop: `pi[n, k, t, s] = inprod(pi[n, k, t - 1, :], Lambda[n, k, t, :, s])`
10. lots of loops; for instance `beta[1]` and `alpha[1]`; `interp.lin`
11. works
12. works
13. similar to 10; contain loops; also `interp.lin`