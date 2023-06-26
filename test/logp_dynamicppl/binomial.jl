model_def = @bugsast begin
    a ~ dbin(0.1, 10)
end

bugs_model = compile(model_def, Dict(), Dict(:a => 10))

@model function dppl_gamma_model()
    return a ~ dbin(0.1, 10)
end

turing_model = dppl_gamma_model()

vi = bugs_model.varinfo

turing_logp_no_trans =
    turing_logp_with_trans = getlogp(
        last(
            DynamicPPL.evaluate!!(
                turing_model, DynamicPPL.settrans!!(vi, false), DynamicPPL.DefaultContext()
            ),
        ),
    )

bugs_logp_no_trans = getlogp(evaluate!!(bugs_model, JuliaBUGS.DefaultContext()))

turing_logp_with_trans = getlogp(
    last(
        DynamicPPL.evaluate!!(
            turing_model, DynamicPPL.settrans!!(vi, true), DynamicPPL.DefaultContext()
        ),
    ),
)

julia_bugs_logp_with_trans = getlogp(
    evaluate!!(JuliaBUGS.settrans!!(bugs_model, true), JuliaBUGS.DefaultContext())
)

@test turing_logp_no_trans ≈ bugs_logp_no_trans atol = 1e-6
@test turing_logp_with_trans ≈ julia_bugs_logp_with_trans atol = 1e-6
