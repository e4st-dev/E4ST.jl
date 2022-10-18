using BenchmarkTools
using E4ST

const SUITE = BenchmarkGroup()


s = 100

SUITE["testrand"] = @benchmarkable rand($s, $s)

SUITE["testzeros"] = @benchmarkable zeros($s, $s)