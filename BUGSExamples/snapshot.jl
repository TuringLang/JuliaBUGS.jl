# Packs the example volumes into the artifact that ships with JuliaBUGS and points
# JuliaBUGS/Artifacts.toml at it. The release tag is derived from the content, so running
# this twice on the same files gives the same tag, tarball, and hashes.
#
#     julia BUGSExamples/snapshot.jl out/
#
# writes out/BUGSExamples.tar.gz and prints the tag to upload it under. The
# BUGSExamplesSnapshot workflow does both on demand.

using Pkg.Artifacts, SHA, Tar

length(ARGS) == 1 || error("usage: snapshot.jl <out-dir>")
out = ARGS[1]
root = @__DIR__
toml = normpath(joinpath(root, "..", "JuliaBUGS", "Artifacts.toml"))

tree = create_artifact() do dir
    for volume in filter(startswith("volume_"), readdir(root))
        cp(joinpath(root, volume), joinpath(dir, volume))
    end
end
tag = "BUGSExamples-" * string(tree)[1:12]
url = "https://github.com/TuringLang/JuliaBUGS.jl/releases/download/$tag/BUGSExamples.tar.gz"

mkpath(out)
tar = joinpath(out, "BUGSExamples.tar")
tarball = tar * ".gz"
rm(tarball; force = true)
Tar.create(artifact_path(tree), tar)
# gzip -n leaves the timestamp out of the header, which is what makes the output reproducible.
run(`gzip -n -9 $tar`)
sha = bytes2hex(open(sha256, tarball))
bind_artifact!(
    toml,
    "BUGSExamples",
    tree;
    lazy = true,
    force = true,
    download_info = [(url, sha)],
)

println("tag      ", tag)
println("tarball  ", tarball)
println("sha256   ", sha)
println("bound    ", toml)
