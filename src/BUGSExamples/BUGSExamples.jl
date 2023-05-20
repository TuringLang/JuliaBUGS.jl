module BUGSExamples

using JuliaBUGS: @bugsast, @bugsmodel_str

function include_children_files(folder_path, exclude_files=String[])
    for file in readdir(folder_path)
        if isfile(joinpath(folder_path, file)) && !(file in exclude_files)
            include(joinpath(folder_path, file))
        end
    end
end

include_children_files("/home/sunxd/JuliaBUGS.jl/src/BUGSExamples/" * "Volume_I")
volume_i_examples = (
    blockers=blockers,
    bones=bones,
    dogs=dogs,
    dyes=dyes,
    epil=epil,
    equiv=equiv,
    # inhalers=inhalers,
    kidney=kidney,
    leuk=leuk,
    leukfr=leukfr,
    lsat=lsat,
    magnesium=magnesium,
    mice=mice,
    oxford=oxford,
    pumps=pumps,
    rats=rats,
    salm=salm,
    seeds=seeds,
    stacks=stacks,
    surgical_simple=surgical_simple,
    surgical_realistic=surgical_realistic,
)

# volume_ii_examples = (birats=birats, eyes=eyes)

end
