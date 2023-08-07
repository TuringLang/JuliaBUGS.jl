using CSV, DataFrames
using JuliaBUGS

# # code for read data into CSV
# filepath = nothing
# df = CSV.read(filepath, DataFrame)
# for col in names(df)
#     if eltype(df[!, col]) == Missing
#         select!(df, Not(col))
#     end
# end
# df = deleteat!(df, length(names(df))) # remove END row
# CSV.write(output_filepath, df)

df = CSV.read("/home/sunxd/JuliaBUGS.jl/test/methadone/data1.csv", DataFrame)
data1 = NamedTuple{Tuple(Symbol.(names(df)))}(Tuple(eachcol(df)))
df = CSV.read("/home/sunxd/JuliaBUGS.jl/test/methadone/data2.csv", DataFrame)
data2 = NamedTuple{Tuple(Symbol.(names(df)))}(Tuple(eachcol(df)))
data3 = (n_nonindexed=184336, n_indexed=240776, n_persons=20410, n_regions=8)
data = merge(data1, data2, data3)

inits = (
    lambda=0,
    beta=[0, 0, 0, 0],
    mu_source=0,
    sd_epsilon=0.5,
    sd_person=0.5,
    sd_source=0.5,
    sd_region=0.5,
    sd_eta=0.5,
)

model_def = @bugs begin
    # Outcomes with person-level data available
    for i in 1:n_indexed
        outcome_y[i] ~ dnorm(mu_indexed[i], tau_epsilon)
        mu_indexed[i] =
            beta[1] * x1[i] +
            beta[2] * x2[i] +
            beta[3] * x3[i] +
            beta[4] * x4[i] +
            region_effect[region_indexed[i]] +
            source_effect[region_indexed[i]] * source_indexed[i] +
            person_effect[person_indexed[i]]
    end

    # Outcomes without person-level data available
    for i in 1:n_nonindexed
        outcome_z[i] ~ dnorm(mu_nonindexed[i], tau_eta)
        mu_nonindexed[i] =
            lambda +
            region_effect[region_nonindexed[i]] +
            source_effect[region_nonindexed[i]] * source_nonindexed[i]
    end

    # Hierarchical priors
    for i in 1:n_persons
        person_effect[i] ~ dnorm(0, tau_person)
    end
    for i in 1:n_regions
        region_effect[i] ~ dnorm(mu_region, tau_region)
        source_effect[i] ~ dnorm(mu_source, tau_source)
    end

    lambda ~ dnorm(0, 0.0001)
    mu_region ~ dnorm(0, 0.0001)
    mu_source ~ dnorm(0, 0.0001)

    # Priors for regression parameters
    for m in 1:4
        beta[m] ~ dnorm(0, 0.0001)
    end

    # Priors for variance parameters
    tau_eta = 1 / pow(sd_eta, 2)
    sd_eta ~ dunif(0, 10)
    tau_epsilon = 1 / pow(sd_epsilon, 2)
    sd_epsilon ~ dunif(0, 10)
    tau_person = 1 / pow(sd_person, 2)
    sd_person ~ dunif(0, 10)
    tau_source = 1 / pow(sd_source, 2)
    sd_source ~ dunif(0, 10)
    tau_region = 1 / pow(sd_region, 2)
    sd_region ~ dunif(0, 10)
end

##
@time model = compile(model_def, data, inits);

@time vars, array_sizes, transformed_variables, array_bitmap = JuliaBUGS.program!(
    JuliaBUGS.CollectVariables(), model_def, data
);

vars, array_sizes, array_bitmap, link_functions, node_args, node_functions, dependencies = JuliaBUGS.program!(
    JuliaBUGS.NodeFunctions(vars, array_sizes, array_bitmap), model_def, data
);
