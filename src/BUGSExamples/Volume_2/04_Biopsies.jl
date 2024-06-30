name = "Biopsies: discrete variable latent class model"

model_def = @bugs begin
    for i in 1:ns
        nbiops[i] = sum(biopsies[i, :])
        var"true"[i] ~ dcat(p[:])
        biopsies[i, 1:4] ~ dmulti(error[var"true"[i], :], nbiops[i])
    end
    error[2, 1:2] ~ ddirich(prior[1:2])
    error[3, 1:3] ~ ddirich(prior[1:3])
    error[4, 1:4] ~ ddirich(prior[1:4])
    p[1:4] ~ ddirich(prior[:]) # prior for p
end

original = """
model
{
   for (i in 1 : ns){
      nbiops[i] <- sum(biopsies[i, ])
      true[i] ~ dcat(p[])
      biopsies[i, 1 : 4] ~ dmulti(error[true[i], ], nbiops[i])
   }
   error[2,1 : 2] ~ ddirich(prior[1 : 2])
   error[3,1 : 3] ~ ddirich(prior[1 : 3])
   error[4,1 : 4] ~ ddirich(prior[1 : 4])
   p[1 : 4] ~ ddirich(prior[]); # prior for p
}
"""

data = (ns = 157,
    error = [1 0 0 0
             missing missing 0 0
             missing missing missing 0
             missing missing missing missing],
    prior = [1, 1, 1, 1],
    biopsies = [2 0 0 0
                2 0 0 0
                2 0 0 0
                2 0 0 0
                2 0 0 0
                2 0 0 0
                2 0 0 0
                2 0 0 0
                2 0 0 0
                2 0 0 0
                2 0 0 0
                2 0 0 0
                1 1 0 0
                1 1 0 0
                1 1 0 0
                1 1 0 0
                1 1 0 0
                1 1 0 0
                1 1 0 0
                1 1 0 0
                1 1 0 0
                1 1 0 0
                0 2 0 0
                0 2 0 0
                0 2 0 0
                0 2 0 0
                1 0 1 0
                1 0 1 0
                1 0 1 0
                1 0 1 0
                1 0 1 0
                1 0 1 0
                1 0 1 0
                1 0 1 0
                1 0 1 0
                0 0 2 0
                0 0 2 0
                0 0 2 0
                0 0 2 0
                0 0 2 0
                0 0 2 0
                0 0 2 0
                0 0 2 0
                0 0 2 0
                0 0 2 0
                0 0 2 0
                0 0 2 0
                1 0 0 1
                0 0 1 1
                0 0 1 1
                0 0 1 1
                0 0 0 2
                0 0 0 2
                0 0 0 2
                0 0 0 2
                0 0 0 2
                0 0 0 2
                3 0 0 0
                3 0 0 0
                3 0 0 0
                3 0 0 0
                3 0 0 0
                3 0 0 0
                3 0 0 0
                3 0 0 0
                3 0 0 0
                3 0 0 0
                3 0 0 0
                3 0 0 0
                3 0 0 0
                3 0 0 0
                3 0 0 0
                3 0 0 0
                3 0 0 0
                3 0 0 0
                3 0 0 0
                3 0 0 0
                3 0 0 0
                3 0 0 0
                3 0 0 0
                3 0 0 0
                3 0 0 0
                3 0 0 0
                3 0 0 0
                3 0 0 0
                2 1 0 0
                2 1 0 0
                2 1 0 0
                2 1 0 0
                2 1 0 0
                2 1 0 0
                2 1 0 0
                2 1 0 0
                2 1 0 0
                2 1 0 0
                2 1 0 0
                2 1 0 0
                2 1 0 0
                1 2 0 0
                1 2 0 0
                1 2 0 0
                1 2 0 0
                1 2 0 0
                1 2 0 0
                1 2 0 0
                1 2 0 0
                1 2 0 0
                1 2 0 0
                0 3 0 0
                2 0 1 0
                2 0 1 0
                2 0 1 0
                2 0 1 0
                2 0 1 0
                2 0 1 0
                2 0 1 0
                2 0 1 0
                2 0 1 0
                1 1 1 0
                0 2 1 0
                1 0 2 0
                1 0 2 0
                1 0 2 0
                1 0 2 0
                1 0 2 0
                1 0 2 0
                1 0 2 0
                1 0 2 0
                1 0 2 0
                1 0 2 0
                1 0 2 0
                1 0 2 0
                1 0 2 0
                1 0 2 0
                1 0 2 0
                1 0 2 0
                1 0 2 0
                0 1 2 0
                0 0 3 0
                0 0 3 0
                0 0 3 0
                0 0 3 0
                0 0 3 0
                0 0 3 0
                0 0 3 0
                0 0 3 0
                2 0 0 1
                1 0 1 1
                0 0 2 1
                0 0 1 2
                0 0 1 2
                0 0 1 2
                0 0 0 3
                0 0 0 3
                0 0 0 3
                0 0 0 3
                0 0 0 3])

intis = (p = [0.25, 0.25, 0.25, 0.25],
    error = [missing missing missing missing
             0.5 0.5 missing missing
             0.33333333 0.33333333 0.33333333 missing])

inits_alternative = (p = [0.4, 0.1, 0.1, 0.4],
    error = [missing missing missing missing
             0.7 0.3 missing missing
             0.2 0.3 0.5 missing
             0.1 0.1 0.1 0.7])

reference_results = (
    var"error[2,1]" = (mean = 0.5875, std = 0.06656),
    var"error[2,2]" = (mean = 0.4125, std = 0.06656),
    var"error[3,1]" = (mean = 0.3416, std = 0.0449),
    var"error[3,2]" = (mean = 0.03708, std = 0.01763),
    var"error[3,3]" = (mean = 0.6213, std = 0.04684),
    var"error[4,1]" = (mean = 0.0992, std = 0.04295),
    var"error[4,2]" = (mean = 0.02187, std = 0.02251),
    var"error[4,3]" = (mean = 0.2055, std = 0.06041),
    var"error[4,4]" = (mean = 0.6734, std = 0.07332),
    var"p[1]" = (mean = 0.1527, std = 0.04979),
    var"p[2]" = (mean = 0.3116, std = 0.05514),
    var"p[3]" = (mean = 0.3886, std = 0.04336),
    var"p[4]" = (mean = 0.1471, std = 0.02971)
)

biopsies = Example(name, model_def, original, data, inits, inits_alternative, reference_results)
