#!perl -T

use Test::More;
eval "use Test::Pod::Coverage 1.04";
plan skip_all => "Test::Pod::Coverage 1.04 required for testing POD coverage" if $@;
all_pod_coverage_ok({
	also_private => [ qr/^(get_master_user_id|master_user_id|user_agent)$/],
});
