"""
    aggregate_generation(data, grouping_col, idxs=(:), yr_idxs=(:), hr_idxs=(:)) -> d::OrderedDict

Aggregate the generation results by `grouping_col`.  Returns an OrderedDict where the keys are the grouping key, and the values are the energy generated.  `idxs`, `yr_idxs` and `hr_idxs` can be flexible (see [`get_row_idxs`](@ref), [`get_year_idxs`](@ref), and [`get_hour_idxs`](@ref)).
"""
function aggregate_generation(data, grouping_col, idxs=(:), yr_idxs=(:), hr_idxs=(:))
    unit = get_table_col_unit(data, :gen, :egen)
    table = get_table(data, :gen, idxs)
    gen = get_table(data, :gen)
    _yr_idxs = get_year_idxs(data, yr_idxs)
    _hr_idxs = get_hour_idxs(data, hr_idxs)
    gdf = groupby(table, grouping_col)
    d = OrderedDict()
    kk = sort(keys(gdf))
    for key in kk
        sdf = gdf[key]
        _idxs = getfield(sdf, :rows)
        d[key] = compute_result(data, :gen, :egen_total, _idxs, _yr_idxs, _hr_idxs)
    end
    return d
end
export aggregate_generation