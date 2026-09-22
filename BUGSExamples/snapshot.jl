# Packs the example volumes into the artifact an installed JuliaBUGS reads and points
# JuliaBUGS/Artifacts.toml at it. The release tag is the content hash, so the same files
# always give the same tag, tarball, and hashes.
#
#     julia BUGSExamples/snapshot.jl out/

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
# gzip -n leaves the timestamp out of the header, which keeps the output reproducible.
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
