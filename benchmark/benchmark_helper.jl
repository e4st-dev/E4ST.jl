using Random
using DataFrames
using OrderedCollections
using CSV
using E4ST

function make_random_inputs(;n_bus = 100, n_gen = 100, n_branch=100, n_af=100, n_hours=100, n_demand = 200, n_demand_shape=100, n_demand_match = 100, n_demand_add = 100, af_file=true, demand_shape_file=true, demand_match_file=true, demand_add_file=true)
    Random.seed!(1)


    ## Make Bus Table
    bus = DataFrame(
        ref_bus = fill(false, n_bus),
        pd = rand(n_bus),
        country = rand(countries(), n_bus)
    )
    ref_bus_idx = rand(1:n_bus)
    bus.ref_bus[ref_bus_idx] = true

    gen = DataFrame(
        bus_idx = rand(1:n_bus, n_gen),
        status = trues(n_gen),
        genfuel = rand(genfuels(), n_gen),
        pcap_min = zeros(n_gen),
        pcap_max = ones(n_gen),
        vom = rand(n_gen),
        fom = rand(n_gen),
        capex = rand(n_gen),
    )
    gt = gentypes()
    gen.gentype = map(gen.genfuel) do gf
        rand(gt[gf])
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
    config = OrderedDict(
        :out_path=>abspath(@__DIR__,"out"),
        :gen_file=>abspath(@__DIR__,"data/gen.csv"),
        :bus_file=>abspath(@__DIR__,"data/bus.csv"),
        :branch_file=>abspath(@__DIR__, "data/branch.csv"),
        :hours_file=>abspath(@__DIR__, "data/time.csv"),
        :years=>years(),
        :optimizer=>OrderedDict(
            :type=>"HiGHS",
        ),
        :mods=>Modification[]
    )
    n_years = length(years())

    demand = rand_demand(;n_bus, n_demand)
    CSV.write(joinpath(@__DIR__, "data/demand.csv"), demand)
    config[:demand_file] = abspath(@__DIR__, "data/demand.csv")

    if af_file
        af = rand_af(;n_hours, n_af)
        CSV.write(joinpath(@__DIR__, "data/af.csv"), af)
        config[:af_file] = abspath(@__DIR__, "data/af.csv")
    end

    if demand_shape_file
        demand_shape = rand_demand_shape(;n_hours, n_demand_shape)
        CSV.write(joinpath(@__DIR__, "data/demand_shape.csv"), demand_shape)
        config[:demand_shape_file] = abspath(@__DIR__, "data/demand_shape.csv")
    end

    if demand_match_file
        demand_match = rand_demand_match(;n_years, n_demand_match)
        CSV.write(joinpath(@__DIR__, "data/demand_match.csv"), demand_match)
        config[:demand_match_file] = abspath(@__DIR__, "data/demand_match.csv")
    end



    if demand_add_file
        demand_add = rand_demand_add(;n_hours, n_demand_add)
        CSV.write(joinpath(@__DIR__, "data/demand_add.csv"), demand_add)
        config[:demand_add_file] = abspath(@__DIR__, "data/demand_add.csv")
    end
    
    return config
end

function years()
    ["y$y" for y in 2030:5:2050]
end
function year_strs()
    year_strs = vcat(years(), "")
end

function load_types()
    ("ev", "residential", "commercial", "industrial", "transportation")
end
function countries()
    ("narnia", "calormen", "archenland", "telmar")
end


function rand_demand(;n_bus, n_demand, kwargs...)
    DataFrame(
        "bus_idx" => rand(1:n_bus, n_demand),
        "pd0" => rand(n_demand),
        "load_type" => rand(load_types())
    )
end

function genfuels()
    ("biomass","nuclear","ng","coal","solar","hydro", "wind", "geothermal")
end
gentypes() = OrderedDict(
    "biomass"=>["biomass","biomass_new"],
    "nuclear"=>["nuclear","nuclear_new"],
    "ng"=>["ng","ng_cc","ng_ccccs"],
    "coal"=>["coal","coal_ccs"],
    "solar"=>["solar","solar_new"],
    "hydro"=>["hydro","hydro_new"],
    "wind"=>["wind","wind_new"],
    "geothermal"=>["hydrothermal","deepgeo_new"],
)

function rand_af(;n_hours, n_af)
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
    gt = gentypes()
    yrs = year_strs()
    while nrow(af) < n_af
        for country in countries()
            joint += 1
            for genfuel in genfuels(), gentype in gt[genfuel]
                year = rand(yrs)
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
    return af
end

function rand_demand_shape(;n_hours, n_demand_shape)
    demand_shape = DataFrame(
        "area" => String[],
        "subarea" => String[],
        "load_type" => String[],
        "year"=>String[],
        "joint" => Int64[],
        "status" => Bool[],
        ("h$n"=>Float64[] for n in 1:n_hours)...
    )
    joint = 1
    gf = genfuels()
    gt = gentypes()
    yrs = year_strs()
    lts = load_types()
    while nrow(demand_shape) < n_demand_shape
        for country in countries()
            joint += 1
            for lt in lts
                year = rand(yrs)
                push!(demand_shape, ("country", country, lt, year, joint, true, rand(n_hours)...))
                if nrow(demand_shape) == n_demand_shape
                    break
                end
            end
            if nrow(demand_shape) == n_demand_shape
                break
            end
        end
    end
    return demand_shape
end

function rand_demand_match(;n_years, n_demand_match)
    demand_match = DataFrame(
        "area" => String[],
        "subarea" => String[],
        "load_type" => String[],
        "joint" => Int64[],
        "status" => Bool[],
        [ys=>Float64[] for ys in years()]...
    )
    joint = 1
    gf = genfuels()
    gt = gentypes()
    lts = load_types()
    while nrow(demand_match) < n_demand_match
        for country in countries()
            joint += 1
            for lt in lts
                push!(demand_match, ("country", country, lt, joint, true, rand(n_years)...))
                if nrow(demand_match) == n_demand_match
                    break
                end
            end
            if nrow(demand_match) == n_demand_match
                break
            end
        end
    end
    return demand_match
end

function rand_demand_add(;n_hours, n_demand_add)
    demand_add = DataFrame(
        "area" => String[],
        "subarea" => String[],
        "load_type" => String[],
        "year"=>String[],
        "joint" => Int64[],
        "status" => Bool[],
        ("h$n"=>Float64[] for n in 1:n_hours)...
    )
    joint = 1
    gf = genfuels()
    gt = gentypes()
    yrs = year_strs()
    lts = load_types()
    while nrow(demand_add) < n_demand_add
        for country in countries()
            joint += 1
            for lt in lts
                year = rand(yrs)
                push!(demand_add, ("country", country, lt, year, joint, true, rand(n_hours)...))
                if nrow(demand_add) == n_demand_add
                    break
                end
            end
            if nrow(demand_add) == n_demand_add
                break
            end
        end
    end
    return demand_add
end