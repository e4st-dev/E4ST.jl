using Random
using DataFrames
using OrderedCollections
using CSV
using E4ST

function make_random_inputs(;n_bus = 100, n_gen = 100, n_branch=100, n_af=100, n_hours=100, n_demand = 200, af_file=true)
    Random.seed!(1)

    countries = ["narnia", "calormen", "archenland", "telmar"]

    ## Make Bus Table
    bus = DataFrame(
        ref_bus = fill(false, n_bus),
        pd = rand(n_bus),
        country = rand(countries, n_bus)
    )
    ref_bus_idx = rand(1:n_bus)
    bus.ref_bus[ref_bus_idx] = true

    genfuels = ["biomass","nuclear","ng","coal","solar","hydro", "wind", "geothermal"]
    gentypes = OrderedDict(
        "biomass"=>["biomass","biomass_new"],
        "nuclear"=>["nuclear","nuclear_new"],
        "ng"=>["ng","ng_cc","ng_ccccs"],
        "coal"=>["coal","coal_ccs"],
        "solar"=>["solar","solar_new"],
        "hydro"=>["hydro","hydro_new"],
        "wind"=>["wind","wind_new"],
        "geothermal"=>["hydrothermal","deepgeo_new"],
    )

    gen = DataFrame(
        bus_idx = rand(1:n_bus, n_gen),
        status = trues(n_gen),
        genfuel = rand(genfuels, n_gen),
        pcap_min = zeros(n_gen),
        pcap0 = ones(n_gen),
        pcap_max = ones(n_gen),
        vom = rand(n_gen),
        fom = rand(n_gen),
        capex = rand(n_gen),
    )
    gen.gentype = map(gen.genfuel) do gf
        rand(gentypes[gf])
    end

    branch = DataFrame(
        f_bus_idx = rand(1:n_bus, n_branch),
        t_bus_idx = rand(1:n_bus, n_branch),
        status = trues(n_branch),
        x = fill(0.01, n_branch),
        pf_max = rand(n_branch)
    )

    

    h = rand(n_hours)
    h = h * 8760/sum(h)
    time = DataFrame(
        hours=h
    )

    isdir(joinpath(@__DIR__,"data")) || mkdir(joinpath(@__DIR__,"data"))
    CSV.write(joinpath(@__DIR__, "data/bus.csv"), bus)
    CSV.write(joinpath(@__DIR__, "data/gen.csv"), gen)
    CSV.write(joinpath(@__DIR__, "data/branch.csv"), branch)
    CSV.write(joinpath(@__DIR__, "data/time.csv"), time)
    years = ["y$y" for y in 2030:5:2050]
    year_strs = vcat(years, "")
    config = OrderedDict(
        :out_path=>abspath(@__DIR__,"out"),
        :gen_file=>abspath(@__DIR__,"data/gen.csv"),
        :bus_file=>abspath(@__DIR__,"data/bus.csv"),
        :branch_file=>abspath(@__DIR__, "data/branch.csv"),
        :hours_file=>abspath(@__DIR__, "data/time.csv"),
        :years=>years,
        :optimizer=>OrderedDict(
            :type=>"HiGHS",
        ),
        :mods=>Modification[]
    )
    if af_file
        af = DataFrame(
            "area" => String[],
            "subarea" => String[],
            "genfuel" => String[],
            "gentype" => String[],
            "year"=>String[],
            "joint" => Int64[],
            "status" => Bool[],
            ("h$n"=>Float64[] for n in 1:n_hours)...
        )
        joint = 1
        while nrow(af) < n_af
            for country in countries
                joint += 1
                for genfuel in genfuels, gentype in gentypes[genfuel]
                    year = rand(year_strs)
                    push!(af, ("country", country, genfuel, gentype, year, joint, true, rand(n_hours)...))
                    if nrow(af) == n_af
                        break
                    end
                end
                if nrow(af) == n_af
                    break
                end
            end
        end

        CSV.write(joinpath(@__DIR__, "data/af.csv"), af)
        config[:af_file] = abspath(@__DIR__, "data/af.csv")

    end

    demand = DataFrame(
        "bus_idx" => rand(1:n_bus, n_demand),
        "pd" => rand(n_demand),
        "load_type" => rand(["ev", "residential", "commercial", "industrial", "transportation"])
    )
    CSV.write(joinpath(@__DIR__, "data/demand.csv"), demand)
    config[:demand_file] = abspath(@__DIR__, "data/demand.csv")
    return config
end