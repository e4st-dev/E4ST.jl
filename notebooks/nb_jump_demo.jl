### A Pluto.jl notebook ###
# v0.19.9

using Markdown
using InteractiveUtils

# ╔═╡ 18e08e80-14d6-11ed-3cc4-d93c8d90b02f
begin
	using JuMP
	using GLPK
end

# ╔═╡ 4fc5f855-8653-4345-9f94-ff8d99623ce5
md"""
# Handy JuMP things for E4ST
"""

# ╔═╡ 22585933-9af9-4edc-9438-52d82ee57b9b
md"""
## Creating a Model
"""

# ╔═╡ 436401f5-f540-4573-ba31-0cdc8729bee7
m = Model(GLPK.Optimizer) # This is where we would put in the solver attributes too

# ╔═╡ f6a50502-4de4-4b2f-be48-942adf71a44d
md"""
## Creating Variables
We'll create some notional variables in the model.  Then we'll make expressions using these variables
"""

# ╔═╡ e018523b-96a8-4d57-9f6f-04539287f87d
gen_ids = [2,5,7,6]

# ╔═╡ 19ab8a6c-b231-437a-9cc8-4b6e68a886ff
n_hours = 7

# ╔═╡ 3e2c2648-b155-43d0-9d20-bb8d226a47cf
hours_weights = begin
	rnd = rand(n_hours)
	rnd/sum(rnd)
end

# ╔═╡ b9940a35-3cae-4079-92a6-39bdea80c050
@variable(m, 0 <= gen[id in gen_ids, hr in 1:n_hours] <= 1.0)

# ╔═╡ 39073fe8-2763-400b-adb0-23e0857ecae4
m[:gen] # Returns the whole set of variables

# ╔═╡ 36d915dd-1797-4fb6-a6bb-5183925b470f
m[:gen][2, :] # Returns the hourly variables for generator with id=2

# ╔═╡ c20d898a-ac41-417e-ad25-6a4084e70e55
gen[2,:]

# ╔═╡ b978d278-fa45-4e52-a2f6-c7089861490c
m[:gen][3, :] # Errors since there is no generator with id=3

# ╔═╡ 0b83125d-0480-4f1a-95dc-b977e2a1cdcb
m[:gen][2, 2] # Returns the variable for the 2nd hour, not sure why it looks weird above

# ╔═╡ 2a3244c8-a5bb-459f-a8bf-f9eb0d549d42
md"""
Now, let's make an expression for the weighted generation for generator 2
"""

# ╔═╡ e63a65ce-49a3-40ad-8d9f-de88863bb9c5
gen2_hourly = sum(m[:gen][2, :] .* hours_weights)

# ╔═╡ 9a3e8621-b3d6-4020-a1c2-910ebe0b0db8
md"""
## Adding Constraints
Say we want to constrain the hourly weighted generation to be less than 0.9
"""

# ╔═╡ ba9cf44d-c2e7-4d05-a82b-cda4b9c395b9
@constraint(m, gen2_hourly <= 0.9)

# ╔═╡ edf203ef-0835-4ff9-b4dd-fb88b9d46323
md"Now say we want to make no generation in hour 7 for all the generators"

# ╔═╡ 8c6ae7bf-ee37-4ae6-8e8e-bdc95b43c509
@constraint(m, m[:gen][:, 7] .== 0)

# ╔═╡ c4d911f4-30a9-4856-aefe-5b7c4b2cce48
md"## Adding to objective function"

# ╔═╡ f3a2db55-4b20-46b2-becb-69da197ea08d
@expression(m, obj, 0) # Initializes an expression called :obj

# ╔═╡ 9e748389-00a9-4a48-aee2-ac97ff07f4af
gen2_vom = 500

# ╔═╡ 039936f1-2a33-47bf-8bd0-14fd983b7129
m[:obj] -= gen2_hourly * gen2_vom

# ╔═╡ 80898733-ee2d-4b7c-86b4-c8b14fbcac98
m[:obj] += 5

# ╔═╡ c7de2c5e-8b69-44d8-bfa1-98089298e43a
m[:obj]

# ╔═╡ ada57c94-9658-466f-a3a9-5655028016f6
m[:obj] *= 5

# ╔═╡ 0e0c24b0-199b-4641-8c50-e9c50716f715
@expression(m, welfare, 10)

# ╔═╡ d9773cbf-843a-467a-aa5a-8a92b913a038
m[:obj] += m[:welfare]

# ╔═╡ dad89c88-3d6a-4f9d-905a-8145b20f7c39
md"Now make the above expression the objective"

# ╔═╡ 7218d4fe-73db-4b7e-aac7-d7a9be782c53
@objective(m, Min, m[:obj]+m[:welfare])

# ╔═╡ c4a8bf17-16ca-47be-aac8-aa7ab8cd0b3d
optimize!(m)

# ╔═╡ f2591537-22d7-40c4-907b-c37fc1bc38bc
value.(gen)

# ╔═╡ abc46416-bd62-48c8-8a55-c8d85e4d32a1
value(m[:obj])

# ╔═╡ df89e977-aaf2-4f56-84c7-7ac4bce19e0e
value(m[:welfare])

# ╔═╡ ffe5e8ad-0f62-4565-8283-7c9a3996634f
value(gen2_hourly)

# ╔═╡ 4a6d5be9-56b4-4ab7-ac23-f85191578fec
gen2_hourly

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
GLPK = "60bf3e95-4087-53dc-ae20-288a0d20c6a6"
JuMP = "4076af6c-e467-56ae-b986-b466b2749572"

[compat]
GLPK = "~1.0.1"
JuMP = "~1.1.1"
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

[[deps.Calculus]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "f641eb0a4f00c343bbc32346e1217b86f3ce9dad"
uuid = "49dc2e85-a5d0-5ad3-a950-438e2897f1b9"
version = "0.5.1"

[[deps.ChainRulesCore]]
deps = ["Compat", "LinearAlgebra", "SparseArrays"]
git-tree-sha1 = "80ca332f6dcb2508adba68f22f551adb2d00a624"
uuid = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
version = "1.15.3"

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
git-tree-sha1 = "924cdca592bc16f14d2f7006754a621735280b74"
uuid = "34da2185-b29b-5c13-b0c7-acf172513d20"
version = "4.1.0"

[[deps.CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"

[[deps.DataStructures]]
deps = ["Compat", "InteractiveUtils", "OrderedCollections"]
git-tree-sha1 = "d1fff3a548102f48987a52a2e0d114fa97d730f0"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.18.13"

[[deps.Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"

[[deps.DiffResults]]
deps = ["StaticArrays"]
git-tree-sha1 = "c18e98cba888c6c25d1c3b048e4b3380ca956805"
uuid = "163ba53b-c6d8-5494-b064-1a9d43ac40c5"
version = "1.0.3"

[[deps.DiffRules]]
deps = ["IrrationalConstants", "LogExpFunctions", "NaNMath", "Random", "SpecialFunctions"]
git-tree-sha1 = "28d605d9a0ac17118fe2c5e9ce0fbb76c3ceb120"
uuid = "b552c78f-8df3-52c6-915a-8e097449b14b"
version = "1.11.0"

[[deps.DocStringExtensions]]
deps = ["LibGit2"]
git-tree-sha1 = "5158c2b41018c5f7eb1470d558127ac274eca0c9"
uuid = "ffbed154-4ef7-542d-bbb7-c09d3a79fcae"
version = "0.9.1"

[[deps.Downloads]]
deps = ["ArgTools", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"

[[deps.ForwardDiff]]
deps = ["CommonSubexpressions", "DiffResults", "DiffRules", "LinearAlgebra", "LogExpFunctions", "NaNMath", "Preferences", "Printf", "Random", "SpecialFunctions", "StaticArrays"]
git-tree-sha1 = "187198a4ed8ccd7b5d99c41b69c679269ea2b2d4"
uuid = "f6369f11-7733-5829-9624-2563aa707210"
version = "0.10.32"

[[deps.GLPK]]
deps = ["GLPK_jll", "MathOptInterface"]
git-tree-sha1 = "c3cc0a7a4e021620f1c0e67679acdbf1be311eb0"
uuid = "60bf3e95-4087-53dc-ae20-288a0d20c6a6"
version = "1.0.1"

[[deps.GLPK_jll]]
deps = ["Artifacts", "GMP_jll", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "fe68622f32828aa92275895fdb324a85894a5b1b"
uuid = "e8aa6df9-e6ca-548a-97ff-1f85fc5b8b98"
version = "5.0.1+0"

[[deps.GMP_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "781609d7-10c4-51f6-84f2-b8444358ff6d"

[[deps.InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"

[[deps.InverseFunctions]]
deps = ["Test"]
git-tree-sha1 = "b3364212fb5d870f724876ffcd34dd8ec6d98918"
uuid = "3587e190-3f89-42d0-90ee-14403ec27112"
version = "0.1.7"

[[deps.IrrationalConstants]]
git-tree-sha1 = "7fd44fd4ff43fc60815f8e764c0f352b83c49151"
uuid = "92d709cd-6900-40b7-9082-c6be49f344b6"
version = "0.1.1"

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
deps = ["Calculus", "DataStructures", "ForwardDiff", "LinearAlgebra", "MathOptInterface", "MutableArithmetics", "NaNMath", "OrderedCollections", "Printf", "SparseArrays", "SpecialFunctions"]
git-tree-sha1 = "534adddf607222b34a0a9bba812248a487ab22b7"
uuid = "4076af6c-e467-56ae-b986-b466b2749572"
version = "1.1.1"

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
git-tree-sha1 = "361c2b088575b07946508f135ac556751240091c"
uuid = "2ab3a3ac-af41-5b50-aa03-7779005ae688"
version = "0.3.17"

[[deps.Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"

[[deps.MacroTools]]
deps = ["Markdown", "Random"]
git-tree-sha1 = "3d3e902b31198a27340d0bf00d6ac452866021cf"
uuid = "1914dd2f-81c6-5fcd-8719-6d5c9610ff09"
version = "0.5.9"

[[deps.Markdown]]
deps = ["Base64"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"

[[deps.MathOptInterface]]
deps = ["BenchmarkTools", "CodecBzip2", "CodecZlib", "DataStructures", "ForwardDiff", "JSON", "LinearAlgebra", "MutableArithmetics", "NaNMath", "OrderedCollections", "Printf", "SparseArrays", "SpecialFunctions", "Test", "Unicode"]
git-tree-sha1 = "e652a21eb0b38849ad84843a50dcbab93313e537"
uuid = "b8f27783-ece8-5eb3-8dc8-9495eed66fee"
version = "1.6.1"

[[deps.MbedTLS_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"

[[deps.Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"

[[deps.MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"

[[deps.MutableArithmetics]]
deps = ["LinearAlgebra", "SparseArrays", "Test"]
git-tree-sha1 = "4e675d6e9ec02061800d6cfb695812becbd03cdf"
uuid = "d8a4904e-b15c-11e9-3269-09a3773c0cb0"
version = "1.0.4"

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
git-tree-sha1 = "0044b23da09b5608b4ecacb4e5e6c6332f833a7e"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.3.2"

[[deps.Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "REPL", "Random", "SHA", "Serialization", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"

[[deps.Preferences]]
deps = ["TOML"]
git-tree-sha1 = "47e5f437cc0e7ef2ce8406ce1e7e24d44915f88d"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.3.0"

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

[[deps.SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"

[[deps.Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"

[[deps.Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"

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
git-tree-sha1 = "23368a3313d12a2326ad0035f0db0c0966f438ef"
uuid = "90137ffa-7385-5640-81b9-e52037218182"
version = "1.5.2"

[[deps.StaticArraysCore]]
git-tree-sha1 = "66fe9eb253f910fe8cf161953880cfdaef01cdf0"
uuid = "1e83bf80-4336-4d27-bf5d-d5a4f845583c"
version = "1.0.1"

[[deps.Statistics]]
deps = ["LinearAlgebra", "SparseArrays"]
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

[[deps.TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"

[[deps.Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"

[[deps.Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[deps.TranscodingStreams]]
deps = ["Random", "Test"]
git-tree-sha1 = "216b95ea110b5972db65aa90f88d8d89dcb8851c"
uuid = "3bb67fe8-82b1-5028-8e26-92a6c54297fa"
version = "0.9.6"

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
# ╠═18e08e80-14d6-11ed-3cc4-d93c8d90b02f
# ╟─4fc5f855-8653-4345-9f94-ff8d99623ce5
# ╟─22585933-9af9-4edc-9438-52d82ee57b9b
# ╠═436401f5-f540-4573-ba31-0cdc8729bee7
# ╟─f6a50502-4de4-4b2f-be48-942adf71a44d
# ╠═e018523b-96a8-4d57-9f6f-04539287f87d
# ╠═19ab8a6c-b231-437a-9cc8-4b6e68a886ff
# ╠═3e2c2648-b155-43d0-9d20-bb8d226a47cf
# ╠═b9940a35-3cae-4079-92a6-39bdea80c050
# ╠═39073fe8-2763-400b-adb0-23e0857ecae4
# ╠═36d915dd-1797-4fb6-a6bb-5183925b470f
# ╠═c20d898a-ac41-417e-ad25-6a4084e70e55
# ╠═b978d278-fa45-4e52-a2f6-c7089861490c
# ╠═0b83125d-0480-4f1a-95dc-b977e2a1cdcb
# ╟─2a3244c8-a5bb-459f-a8bf-f9eb0d549d42
# ╠═e63a65ce-49a3-40ad-8d9f-de88863bb9c5
# ╟─9a3e8621-b3d6-4020-a1c2-910ebe0b0db8
# ╠═ba9cf44d-c2e7-4d05-a82b-cda4b9c395b9
# ╟─edf203ef-0835-4ff9-b4dd-fb88b9d46323
# ╠═8c6ae7bf-ee37-4ae6-8e8e-bdc95b43c509
# ╟─c4d911f4-30a9-4856-aefe-5b7c4b2cce48
# ╠═f3a2db55-4b20-46b2-becb-69da197ea08d
# ╠═9e748389-00a9-4a48-aee2-ac97ff07f4af
# ╠═039936f1-2a33-47bf-8bd0-14fd983b7129
# ╠═80898733-ee2d-4b7c-86b4-c8b14fbcac98
# ╠═c7de2c5e-8b69-44d8-bfa1-98089298e43a
# ╠═ada57c94-9658-466f-a3a9-5655028016f6
# ╠═0e0c24b0-199b-4641-8c50-e9c50716f715
# ╠═d9773cbf-843a-467a-aa5a-8a92b913a038
# ╟─dad89c88-3d6a-4f9d-905a-8145b20f7c39
# ╠═7218d4fe-73db-4b7e-aac7-d7a9be782c53
# ╠═c4a8bf17-16ca-47be-aac8-aa7ab8cd0b3d
# ╠═f2591537-22d7-40c4-907b-c37fc1bc38bc
# ╠═abc46416-bd62-48c8-8a55-c8d85e4d32a1
# ╠═df89e977-aaf2-4f56-84c7-7ac4bce19e0e
# ╠═ffe5e8ad-0f62-4565-8283-7c9a3996634f
# ╠═4a6d5be9-56b4-4ab7-ac23-f85191578fec
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
