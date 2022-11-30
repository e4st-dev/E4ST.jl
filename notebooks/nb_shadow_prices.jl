### A Pluto.jl notebook ###
# v0.19.9

using Markdown
using InteractiveUtils

# ╔═╡ b4298130-55f9-11ed-2cad-5d00ccdb5f95
begin
	using JuMP
	using HiGHS
	using DataFrames
end

# ╔═╡ 47c5bd37-63fb-4ad6-829a-28c8c62aea08
md"""
# Shadow Prices Demonstration
"""

# ╔═╡ c14335c1-70b9-49e7-971f-6e9c2ad707ca
md"""
Let's make a super simple 3-bus, 2 generator DCOPF to optimize!

The first and third buses have generators, with different max powers and different emission rates.  The first and third buses connect to the second, but they don't connect to each other.
"""

# ╔═╡ 67e8d304-29bf-4c1b-af0b-b1b001a8cb37
bus = DataFrame(
	:load   => [0.2, 1.6, 0.2],
)

# ╔═╡ afde213e-f796-4a0e-aad3-a844293397d2
gen = DataFrame(
	:bus_id => [1, 3],
	:pg_min => [0.0, 0.0],
	:pg_max => [1.2, 2.0],
	:r_emis => [0.1, 0.15]
)

# ╔═╡ 8dae7b7c-f8b4-4ef5-85f8-8b5e796d29ce
branch = DataFrame(
	:f_bus => [1, 3],
	:t_bus => [2, 2],
	:x     => [0.01, 0.01]
)

# ╔═╡ e26f8a31-0256-4a4a-b9fd-8ec453490f8a
begin
	bus2buses = map(r->Int64[], eachrow(bus))
	buses2branch = Dict{Tuple{Int64, Int64}, Int64}()
	for i in 1:nrow(branch)
		f_bus_id = branch.f_bus[i]
		t_bus_id = branch.t_bus[i]
		buses2branch[(f_bus_id, t_bus_id)] = i
		buses2branch[(t_bus_id, f_bus_id)] = -i
		push!(bus2buses[f_bus_id], t_bus_id)
		push!(bus2buses[t_bus_id], f_bus_id)
	end
	bus.connected_buses = bus2buses
	ref_bus = 2
	emis_price = 100
	data = (;bus, branch, gen, buses2branch, ref_bus, emis_price)
end

# ╔═╡ 70b822a0-17ec-458e-b2ce-5e43132ece7e
function is_branch(data, f_bus, t_bus)
	haskey(data.buses2branch, (f_bus, t_bus))
end

# ╔═╡ bdc880c6-0e5e-482d-84d7-0d4855eeb5d1
function get_branch_id(data, f_bus, t_bus)
	data.buses2branch[(f_bus, t_bus)]
end

# ╔═╡ 52cb2cd6-a55b-4e48-8222-516b8a44a252
function get_connected_buses(data, f_bus)
	return data.bus.connected_buses[f_bus]
end

# ╔═╡ a290fb9c-dad3-433c-bf35-6393168c525a
function get_reactance(data, f_bus, t_bus)
	i_br = get_branch_id(data, f_bus, t_bus)
	i_br > 0 ? data.branch.x[i_br] : data.branch.x[-i_br]
end

# ╔═╡ 846ad4b2-f7d5-435b-bed2-08a00a1bae08
function get_voltage_angle(data, m, f_bus, t_bus)
	m[:va][t_bus] - m[:va][f_bus]
end

# ╔═╡ f5ff4b36-ad33-4e3c-96ec-b8f18425f1ce
function get_power_flow(data, m, f_bus, t_bus)
	Δva = get_voltage_angle(data, m, f_bus, t_bus)
	x = get_reactance(data, f_bus, t_bus)
	return Δva / x 
end	

# ╔═╡ 458e45df-5d9b-4811-85bb-f31f0c1a1178
function get_power_flow(data, m, f_bus)
	sum(t_bus->get_power_flow(data, m, f_bus, t_bus), get_connected_buses(data, f_bus))
end

# ╔═╡ 62a3d54a-58a7-40c8-860b-e709c75a9dcc
function get_gen_ids(data, bus_id)
	findall(id-> id==bus_id, data.gen.bus_id)
	# TODO: maybe later put a column in bus for gen_ids attached.
end

# ╔═╡ a4f21c61-57b4-4bd0-9efb-91da984afb4e
function get_power_gen(data, m, gen_id)
	return m[:pg][gen_id]
end

# ╔═╡ 1e304d59-dac3-4d9b-a335-e788e87b7d06
function get_pg_bus(data, m, bus_id)
	gen_ids = get_gen_ids(data, bus_id)
	isempty(gen_ids) && return 0.0
	return sum(gen_id->get_power_gen(data, m, gen_id), gen_ids)
end

# ╔═╡ 6315975c-d474-4119-b13f-88fa4f58dab6
function get_load_bus(data, m, bus_id)
	data.bus.load[bus_id]
end

# ╔═╡ ac6ac937-a3ba-4b5a-bc87-b1f49802f36e
function get_emissions_gen(data, m, gen_id)
	return m[:pg][gen_id] * data.gen.r_emis[gen_id]
end

# ╔═╡ fcf929b7-9326-4d14-bafa-b8a0e5fe99e0
function get_emissions_bus(data, m, bus_id)
	gen_ids = get_gen_ids(data, bus_id)
	isempty(gen_ids) && return 0.0
	return sum(gen_id->get_emissions_gen(data, m, gen_id), gen_ids)
end

# ╔═╡ 4b64cc92-4448-4b42-9bec-fa6c2a918395
md"""
# Make Model
"""

# ╔═╡ de0d8c1e-45c1-4352-b48d-c78c80c00de5
begin
	

	m = Model(HiGHS.Optimizer)
	
	# Voltage Angle
	@variable(m, va[bus_id in 1:nrow(bus)])
	
	# Power Generation
	@variable(m, pg[gen_id in 1:nrow(data.gen)])

	# Constrain Power Flow
	@constraint(m, 
		cons_pf[bus_id in 1:nrow(data.bus)], 
		get_pg_bus(data, m, bus_id) - get_load_bus(data, m, bus_id) == get_power_flow(data, m, bus_id)
	)

	# Constrain Reference Bus
	@constraint(m, cons_ref_bus, m[:va][data.ref_bus] == 0)

	# Constrain Power Generation
	@constraint(m, cons_pg_min[gen_id in 1:nrow(data.gen)],
		pg[gen_id] >= data.gen.pg_min[gen_id]
	)
	@constraint(m, cons_pg_max[gen_id in 1:nrow(data.gen)],
		pg[gen_id] <= data.gen.pg_max[gen_id]
	)

	# Add objective to minimize emissions cost
	@objective(m, Min, sum(bus_id->get_emissions_bus(data,m,bus_id) * data.emis_price, 1:nrow(data.bus)))

	optimize!(m)
	
end

# ╔═╡ e5eff881-1270-4ddd-8367-6629a1046b24
md"""
# Analyzing the Model Results

## Generator Results
"""

# ╔═╡ a9e97548-db23-4dcc-a860-03f147bd1cf1
begin
data.gen.pg = value.(m[:pg])
data.gen
end

# ╔═╡ 835ba56d-832c-4ac5-8edd-0465631ec892
md"We can see above that the model solves for power generation **pg**, and finds that the first generator operates to its max (because of its lower emissions rate), and the second generator operates as much as it needs to in order to reach the total required load of 2.  This looks about right!"

# ╔═╡ bbf39c70-d8e2-48ff-8b87-efbe3a28fa25
md"""
## Branch Results
* We expect to see 1.0 flow from 1->2 (1.2 generated - 0.2 load)
* We expect to see 0.6 flow from 3->2 (0.8 generated - 0.2 load)
"""

# ╔═╡ bb841890-31db-44bb-bd76-3fcc257aef99
begin
data.branch.pf = map(br->value(get_power_flow(data,m,br.f_bus,br.t_bus)), eachrow(data.branch))
data.branch
end

# ╔═╡ 118808cb-eb96-49f0-b9f4-b3615da5f9a8
md"""
## Max Generation Constraint
$P^G_i <=  P^G_{i_max} \qquad \forall i \in \text{Gen}$
Now let's take a look at shadow prices.  Shadow prices on a constraint are \"the change in the objective from an infinitesimal relaxation of the constraint.\"  
 First, we'll look at the shadow price on the max generation constraint.  This will tell us the rate of change in the objective function from allowing an additional generation from each generator.  We would expect that the constraint for generator 1 would be binding because pg==pg_max, but we would expect the constraint not to bind for generator 2 since we're not maxing out generation.  We'd expect that to be the difference in emissions rates times the emission price, so \$100*(0.15-0.1) = 5.  We would also expect that to be negative since that would lower the total carbon cost.  A look at the shadow price calculated below:
"""

# ╔═╡ a5720966-1fc3-42c6-be59-4e7e60ce5f07
begin
data.gen.prc_pg_max = shadow_price.(cons_pg_max)
data.gen
end

# ╔═╡ 51b2c52d-ca98-4de3-b817-8137cc24702e
md"""
## Power Flow Constraint
$\sum_{g \in gen_i}P^G_g - P^L_i = \sum_{(i,j) \, \in \, \text{Branches}} p_{i,j}  \qquad  \forall i \in \text{Buses}$
Now let's look at what would happen if we relaxed one of the power flow constraints.  Conceptually, relaxing this constraint would be saying that generation does not need to equal load (or something similar to that).  If we didn't need to meet load, the first thing we'd do is stop generating with the most expensive generator since we can simply create power out of thin air, which would reduce the objective function at a rate of 0.15*\$100 = \$15.  We would expect this to be the same for each node. 
"""

# ╔═╡ 8dc01acc-eb4d-4a63-b3ea-7542175c3d61
shadow_price.(cons_pf)

# ╔═╡ 822fef62-c62a-4be5-9146-d3ceecddb06e
md"""
## Reference Bus Constraint
We would expect that the reference bus would not have any effect on our objective function, so the shadow price would be zero.
"""

# ╔═╡ cd8cf972-af98-4f8e-bf60-c0c7af662f92
shadow_price(cons_ref_bus)

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
HiGHS = "87dc4568-4c63-4d18-b0c0-bb2238e4078b"
JuMP = "4076af6c-e467-56ae-b986-b466b2749572"

[compat]
DataFrames = "~1.4.1"
HiGHS = "~1.1.4"
JuMP = "~1.3.1"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.7.2"
manifest_format = "2.0"

[[deps.ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"

[[deps.Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"

[[deps.Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"

[[deps.BenchmarkTools]]
deps = ["JSON", "Logging", "Printf", "Profile", "Statistics", "UUIDs"]
git-tree-sha1 = "4c10eee4af024676200bc7752e536f858c6b8f93"
uuid = "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf"
version = "1.3.1"

[[deps.Bzip2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "19a35467a82e236ff51bc17a3a44b69ef35185a2"
uuid = "6e34b625-4abd-537c-b88f-471c36dfa7a0"
version = "1.0.8+0"

[[deps.ChainRulesCore]]
deps = ["Compat", "LinearAlgebra", "SparseArrays"]
git-tree-sha1 = "e7ff6cadf743c098e08fca25c91103ee4303c9bb"
uuid = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
version = "1.15.6"

[[deps.ChangesOfVariables]]
deps = ["ChainRulesCore", "LinearAlgebra", "Test"]
git-tree-sha1 = "38f7a08f19d8810338d4f5085211c7dfa5d5bdd8"
uuid = "9e997f8a-9a97-42d5-a9f1-ce6bfc15e2c0"
version = "0.1.4"

[[deps.CodecBzip2]]
deps = ["Bzip2_jll", "Libdl", "TranscodingStreams"]
git-tree-sha1 = "2e62a725210ce3c3c2e1a3080190e7ca491f18d7"
uuid = "523fee87-0ab8-5b00-afb7-3ecf72e48cfd"
version = "0.7.2"

[[deps.CodecZlib]]
deps = ["TranscodingStreams", "Zlib_jll"]
git-tree-sha1 = "ded953804d019afa9a3f98981d99b33e3db7b6da"
uuid = "944b1d66-785c-5afd-91f1-9de20f533193"
version = "0.7.0"

[[deps.CommonSubexpressions]]
deps = ["MacroTools", "Test"]
git-tree-sha1 = "7b8a93dba8af7e3b42fecabf646260105ac373f7"
uuid = "bbf7d656-a473-5ed7-a52c-81e309532950"
version = "0.3.0"

[[deps.Compat]]
deps = ["Dates", "LinearAlgebra", "UUIDs"]
git-tree-sha1 = "3ca828fe1b75fa84b021a7860bd039eaea84d2f2"
uuid = "34da2185-b29b-5c13-b0c7-acf172513d20"
version = "4.3.0"

[[deps.CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"

[[deps.Crayons]]
git-tree-sha1 = "249fe38abf76d48563e2f4556bebd215aa317e15"
uuid = "a8cc5b0e-0ffa-5ad4-8c14-923d3ee1735f"
version = "4.1.1"

[[deps.DataAPI]]
git-tree-sha1 = "46d2680e618f8abd007bce0c3026cb0c4a8f2032"
uuid = "9a962f9c-6df0-11e9-0e5d-c546b8b5ee8a"
version = "1.12.0"

[[deps.DataFrames]]
deps = ["Compat", "DataAPI", "Future", "InvertedIndices", "IteratorInterfaceExtensions", "LinearAlgebra", "Markdown", "Missings", "PooledArrays", "PrettyTables", "Printf", "REPL", "Random", "Reexport", "SnoopPrecompile", "SortingAlgorithms", "Statistics", "TableTraits", "Tables", "Unicode"]
git-tree-sha1 = "558078b0b78278683a7445c626ee78c86b9bb000"
uuid = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
version = "1.4.1"

[[deps.DataStructures]]
deps = ["Compat", "InteractiveUtils", "OrderedCollections"]
git-tree-sha1 = "d1fff3a548102f48987a52a2e0d114fa97d730f0"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.18.13"

[[deps.DataValueInterfaces]]
git-tree-sha1 = "bfc1187b79289637fa0ef6d4436ebdfe6905cbd6"
uuid = "e2d170a0-9d28-54be-80f0-106bbe20a464"
version = "1.0.0"

[[deps.Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"

[[deps.DiffResults]]
deps = ["StaticArraysCore"]
git-tree-sha1 = "782dd5f4561f5d267313f23853baaaa4c52ea621"
uuid = "163ba53b-c6d8-5494-b064-1a9d43ac40c5"
version = "1.1.0"

[[deps.DiffRules]]
deps = ["IrrationalConstants", "LogExpFunctions", "NaNMath", "Random", "SpecialFunctions"]
git-tree-sha1 = "992a23afdb109d0d2f8802a30cf5ae4b1fe7ea68"
uuid = "b552c78f-8df3-52c6-915a-8e097449b14b"
version = "1.11.1"

[[deps.DocStringExtensions]]
deps = ["LibGit2"]
git-tree-sha1 = "5158c2b41018c5f7eb1470d558127ac274eca0c9"
uuid = "ffbed154-4ef7-542d-bbb7-c09d3a79fcae"
version = "0.9.1"

[[deps.Downloads]]
deps = ["ArgTools", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"

[[deps.Formatting]]
deps = ["Printf"]
git-tree-sha1 = "8339d61043228fdd3eb658d86c926cb282ae72a8"
uuid = "59287772-0a20-5a39-b81b-1366585eb4c0"
version = "0.4.2"

[[deps.ForwardDiff]]
deps = ["CommonSubexpressions", "DiffResults", "DiffRules", "LinearAlgebra", "LogExpFunctions", "NaNMath", "Preferences", "Printf", "Random", "SpecialFunctions", "StaticArrays"]
git-tree-sha1 = "187198a4ed8ccd7b5d99c41b69c679269ea2b2d4"
uuid = "f6369f11-7733-5829-9624-2563aa707210"
version = "0.10.32"

[[deps.Future]]
deps = ["Random"]
uuid = "9fa8497b-333b-5362-9e8d-4d0656e87820"

[[deps.HiGHS]]
deps = ["HiGHS_jll", "MathOptInterface", "SparseArrays"]
git-tree-sha1 = "dc1802d0710a6e685d4279d0d3e6ae5fe35203fe"
uuid = "87dc4568-4c63-4d18-b0c0-bb2238e4078b"
version = "1.1.4"

[[deps.HiGHS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "b0bf110765a077880aab84876f9f0b8de0407561"
uuid = "8fd58aa0-07eb-5a78-9b36-339c94fd15ea"
version = "1.2.2+0"

[[deps.InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"

[[deps.InverseFunctions]]
deps = ["Test"]
git-tree-sha1 = "49510dfcb407e572524ba94aeae2fced1f3feb0f"
uuid = "3587e190-3f89-42d0-90ee-14403ec27112"
version = "0.1.8"

[[deps.InvertedIndices]]
git-tree-sha1 = "bee5f1ef5bf65df56bdd2e40447590b272a5471f"
uuid = "41ab1584-1d38-5bbf-9106-f11c6c58b48f"
version = "1.1.0"

[[deps.IrrationalConstants]]
git-tree-sha1 = "7fd44fd4ff43fc60815f8e764c0f352b83c49151"
uuid = "92d709cd-6900-40b7-9082-c6be49f344b6"
version = "0.1.1"

[[deps.IteratorInterfaceExtensions]]
git-tree-sha1 = "a3f24677c21f5bbe9d2a714f95dcd58337fb2856"
uuid = "82899510-4779-5014-852e-03e436cf321d"
version = "1.0.0"

[[deps.JLLWrappers]]
deps = ["Preferences"]
git-tree-sha1 = "abc9885a7ca2052a736a600f7fa66209f96506e1"
uuid = "692b3bcd-3c85-4b1f-b108-f13ce0eb3210"
version = "1.4.1"

[[deps.JSON]]
deps = ["Dates", "Mmap", "Parsers", "Unicode"]
git-tree-sha1 = "3c837543ddb02250ef42f4738347454f95079d4e"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "0.21.3"

[[deps.JuMP]]
deps = ["LinearAlgebra", "MathOptInterface", "MutableArithmetics", "OrderedCollections", "Printf", "SparseArrays"]
git-tree-sha1 = "8c0aacbcb0530d6fdc2650fe8cd312e7da452dbc"
uuid = "4076af6c-e467-56ae-b986-b466b2749572"
version = "1.3.1"

[[deps.LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"

[[deps.LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"

[[deps.LibGit2]]
deps = ["Base64", "NetworkOptions", "Printf", "SHA"]
uuid = "76f85450-5226-5b5a-8eaa-529ad045b433"

[[deps.LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "MbedTLS_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"

[[deps.Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"

[[deps.LinearAlgebra]]
deps = ["Libdl", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"

[[deps.LogExpFunctions]]
deps = ["ChainRulesCore", "ChangesOfVariables", "DocStringExtensions", "InverseFunctions", "IrrationalConstants", "LinearAlgebra"]
git-tree-sha1 = "94d9c52ca447e23eac0c0f074effbcd38830deb5"
uuid = "2ab3a3ac-af41-5b50-aa03-7779005ae688"
version = "0.3.18"

[[deps.Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"

[[deps.MacroTools]]
deps = ["Markdown", "Random"]
git-tree-sha1 = "42324d08725e200c23d4dfb549e0d5d89dede2d2"
uuid = "1914dd2f-81c6-5fcd-8719-6d5c9610ff09"
version = "0.5.10"

[[deps.Markdown]]
deps = ["Base64"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"

[[deps.MathOptInterface]]
deps = ["BenchmarkTools", "CodecBzip2", "CodecZlib", "DataStructures", "ForwardDiff", "JSON", "LinearAlgebra", "MutableArithmetics", "NaNMath", "OrderedCollections", "Printf", "SparseArrays", "SpecialFunctions", "Test", "Unicode"]
git-tree-sha1 = "2284cb18c8670fd5c57ad010ce9bd4e2901692d2"
uuid = "b8f27783-ece8-5eb3-8dc8-9495eed66fee"
version = "1.8.2"

[[deps.MbedTLS_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"

[[deps.Missings]]
deps = ["DataAPI"]
git-tree-sha1 = "bf210ce90b6c9eed32d25dbcae1ebc565df2687f"
uuid = "e1d29d7a-bbdc-5cf2-9ac0-f12de2c33e28"
version = "1.0.2"

[[deps.Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"

[[deps.MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"

[[deps.MutableArithmetics]]
deps = ["LinearAlgebra", "SparseArrays", "Test"]
git-tree-sha1 = "1d57a7dc42d563ad6b5e95d7a8aebd550e5162c0"
uuid = "d8a4904e-b15c-11e9-3269-09a3773c0cb0"
version = "1.0.5"

[[deps.NaNMath]]
deps = ["OpenLibm_jll"]
git-tree-sha1 = "a7c3d1da1189a1c2fe843a3bfa04d18d20eb3211"
uuid = "77ba4419-2d1f-58cd-9bb1-8ffee604a2e3"
version = "1.0.1"

[[deps.NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"

[[deps.OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"

[[deps.OpenLibm_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "05823500-19ac-5b8b-9628-191a04bc5112"

[[deps.OpenSpecFun_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "13652491f6856acfd2db29360e1bbcd4565d04f1"
uuid = "efe28fd5-8261-553b-a9e1-b2916fc3738e"
version = "0.5.5+0"

[[deps.OrderedCollections]]
git-tree-sha1 = "85f8e6578bf1f9ee0d11e7bb1b1456435479d47c"
uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
version = "1.4.1"

[[deps.Parsers]]
deps = ["Dates"]
git-tree-sha1 = "6c01a9b494f6d2a9fc180a08b182fcb06f0958a0"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.4.2"

[[deps.Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "REPL", "Random", "SHA", "Serialization", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"

[[deps.PooledArrays]]
deps = ["DataAPI", "Future"]
git-tree-sha1 = "a6062fe4063cdafe78f4a0a81cfffb89721b30e7"
uuid = "2dfb63ee-cc39-5dd5-95bd-886bf059d720"
version = "1.4.2"

[[deps.Preferences]]
deps = ["TOML"]
git-tree-sha1 = "47e5f437cc0e7ef2ce8406ce1e7e24d44915f88d"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.3.0"

[[deps.PrettyTables]]
deps = ["Crayons", "Formatting", "Markdown", "Reexport", "StringManipulation", "Tables"]
git-tree-sha1 = "460d9e154365e058c4d886f6f7d6df5ffa1ea80e"
uuid = "08abe8d2-0d0c-5749-adfa-8a2ac140af0d"
version = "2.1.2"

[[deps.Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"

[[deps.Profile]]
deps = ["Printf"]
uuid = "9abbd945-dff8-562f-b5e8-e1ebf5ef1b79"

[[deps.REPL]]
deps = ["InteractiveUtils", "Markdown", "Sockets", "Unicode"]
uuid = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"

[[deps.Random]]
deps = ["SHA", "Serialization"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

[[deps.Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[deps.SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"

[[deps.Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"

[[deps.SnoopPrecompile]]
git-tree-sha1 = "f604441450a3c0569830946e5b33b78c928e1a85"
uuid = "66db9d55-30c0-4569-8b51-7e840670fc0c"
version = "1.0.1"

[[deps.Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"

[[deps.SortingAlgorithms]]
deps = ["DataStructures"]
git-tree-sha1 = "b3363d7460f7d098ca0912c69b082f75625d7508"
uuid = "a2af1166-a08f-5f64-846c-94a0d3cef48c"
version = "1.0.1"

[[deps.SparseArrays]]
deps = ["LinearAlgebra", "Random"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"

[[deps.SpecialFunctions]]
deps = ["ChainRulesCore", "IrrationalConstants", "LogExpFunctions", "OpenLibm_jll", "OpenSpecFun_jll"]
git-tree-sha1 = "d75bda01f8c31ebb72df80a46c88b25d1c79c56d"
uuid = "276daf66-3868-5448-9aa4-cd146d93841b"
version = "2.1.7"

[[deps.StaticArrays]]
deps = ["LinearAlgebra", "Random", "StaticArraysCore", "Statistics"]
git-tree-sha1 = "f86b3a049e5d05227b10e15dbb315c5b90f14988"
uuid = "90137ffa-7385-5640-81b9-e52037218182"
version = "1.5.9"

[[deps.StaticArraysCore]]
git-tree-sha1 = "6b7ba252635a5eff6a0b0664a41ee140a1c9e72a"
uuid = "1e83bf80-4336-4d27-bf5d-d5a4f845583c"
version = "1.4.0"

[[deps.Statistics]]
deps = ["LinearAlgebra", "SparseArrays"]
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

[[deps.StringManipulation]]
git-tree-sha1 = "46da2434b41f41ac3594ee9816ce5541c6096123"
uuid = "892a3eda-7b42-436c-8928-eab12a02cf0e"
version = "0.3.0"

[[deps.TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"

[[deps.TableTraits]]
deps = ["IteratorInterfaceExtensions"]
git-tree-sha1 = "c06b2f539df1c6efa794486abfb6ed2022561a39"
uuid = "3783bdb8-4a98-5b6b-af9a-565f29a5fe9c"
version = "1.0.1"

[[deps.Tables]]
deps = ["DataAPI", "DataValueInterfaces", "IteratorInterfaceExtensions", "LinearAlgebra", "OrderedCollections", "TableTraits", "Test"]
git-tree-sha1 = "c79322d36826aa2f4fd8ecfa96ddb47b174ac78d"
uuid = "bd369af6-aec1-5ad0-b16a-f7cc5008161c"
version = "1.10.0"

[[deps.Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"

[[deps.Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[deps.TranscodingStreams]]
deps = ["Random", "Test"]
git-tree-sha1 = "8a75929dcd3c38611db2f8d08546decb514fcadf"
uuid = "3bb67fe8-82b1-5028-8e26-92a6c54297fa"
version = "0.9.9"

[[deps.UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"

[[deps.Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"

[[deps.Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"

[[deps.libblastrampoline_jll]]
deps = ["Artifacts", "Libdl", "OpenBLAS_jll"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"

[[deps.nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"

[[deps.p7zip_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"
"""

# ╔═╡ Cell order:
# ╟─47c5bd37-63fb-4ad6-829a-28c8c62aea08
# ╠═b4298130-55f9-11ed-2cad-5d00ccdb5f95
# ╟─c14335c1-70b9-49e7-971f-6e9c2ad707ca
# ╠═67e8d304-29bf-4c1b-af0b-b1b001a8cb37
# ╠═afde213e-f796-4a0e-aad3-a844293397d2
# ╠═8dae7b7c-f8b4-4ef5-85f8-8b5e796d29ce
# ╠═e26f8a31-0256-4a4a-b9fd-8ec453490f8a
# ╠═70b822a0-17ec-458e-b2ce-5e43132ece7e
# ╠═bdc880c6-0e5e-482d-84d7-0d4855eeb5d1
# ╠═52cb2cd6-a55b-4e48-8222-516b8a44a252
# ╠═a290fb9c-dad3-433c-bf35-6393168c525a
# ╠═846ad4b2-f7d5-435b-bed2-08a00a1bae08
# ╠═f5ff4b36-ad33-4e3c-96ec-b8f18425f1ce
# ╠═458e45df-5d9b-4811-85bb-f31f0c1a1178
# ╠═62a3d54a-58a7-40c8-860b-e709c75a9dcc
# ╠═1e304d59-dac3-4d9b-a335-e788e87b7d06
# ╠═a4f21c61-57b4-4bd0-9efb-91da984afb4e
# ╠═6315975c-d474-4119-b13f-88fa4f58dab6
# ╠═fcf929b7-9326-4d14-bafa-b8a0e5fe99e0
# ╠═ac6ac937-a3ba-4b5a-bc87-b1f49802f36e
# ╟─4b64cc92-4448-4b42-9bec-fa6c2a918395
# ╠═de0d8c1e-45c1-4352-b48d-c78c80c00de5
# ╟─e5eff881-1270-4ddd-8367-6629a1046b24
# ╠═a9e97548-db23-4dcc-a860-03f147bd1cf1
# ╟─835ba56d-832c-4ac5-8edd-0465631ec892
# ╟─bbf39c70-d8e2-48ff-8b87-efbe3a28fa25
# ╠═bb841890-31db-44bb-bd76-3fcc257aef99
# ╟─118808cb-eb96-49f0-b9f4-b3615da5f9a8
# ╠═a5720966-1fc3-42c6-be59-4e7e60ce5f07
# ╟─51b2c52d-ca98-4de3-b817-8137cc24702e
# ╠═8dc01acc-eb4d-4a63-b3ea-7542175c3d61
# ╟─822fef62-c62a-4be5-9146-d3ceecddb06e
# ╠═cd8cf972-af98-4f8e-bf60-c0c7af662f92
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
