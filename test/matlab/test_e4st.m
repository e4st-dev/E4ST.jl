function test_e4st(verbose)
%TEST_E4ST  Run all MATPOWER tests.
%   TEST_E4ST runs all of the E4ST tests.
%   TEST_E4ST(VERBOSE) prints the details of the individual tests
%   if VERBOSE is true.
%
%   See also T_RUN_TESTS.

%   E4ST
%   Copyright (c) 2004-2016 by Power System Engineering Research Center (PSERC)
%   by Ray Zimmerman, PSERC Cornell
%
%   This file is part of E4ST.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See http://e4st.com/ for more info.

if nargin < 1
    verbose = 0;
end

tests = {};

tests{end+1} = 't_apply_changes';
tests{end+1} = 't_e4st_solve';
tests{end+1} = 't_e4st_caplim';
tests{end+1} = 't_e4st_storage';
tests{end+1} = 't_e4st_dac';

t_run_tests( tests, verbose );
