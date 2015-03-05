# @TEST-SERIALIZE: brokercomm
# @TEST-REQUIRES: grep -q ENABLE_BROKER $BUILD/CMakeCache.txt

# @TEST-EXEC: btest-bg-run clone "bro -b -r $TRACES/wikipedia.trace ../clone.bro broker_port=$BROKER_PORT >clone.out"
# @TEST-EXEC: btest-bg-run master "bro -b -r $TRACES/wikipedia.trace ../master.bro broker_port=$BROKER_PORT >master.out"

# @TEST-EXEC: btest-bg-wait 20
# @TEST-EXEC: TEST_DIFF_CANONIFIER=$SCRIPTS/diff-sort btest-diff clone/clone.out
# @TEST-EXEC: btest-diff master/master.out

@TEST-START-FILE clone.bro

const broker_port: port &redef;
redef exit_only_after_terminate = T;

global h: opaque of Store::Handle;
global expected_key_count = 4;
global key_count = 0;

global query_timeout = 15sec;

function do_lookup(key: string)
	{
	when ( local res = Store::lookup(h, Comm::data(key)) )
		{
		++key_count;
		print "lookup", key, res;

		if ( key_count == expected_key_count )
			terminate();
		}
	timeout query_timeout
		{
		print "clone lookup query timeout";
		terminate();
		}
	}

event ready()
	{
	h = Store::create_clone("mystore");

	when ( local res = Store::keys(h) )
		{
		print "clone keys", res;
		do_lookup(Comm::refine_to_string(Comm::vector_lookup(res$result, 0)));
		do_lookup(Comm::refine_to_string(Comm::vector_lookup(res$result, 1)));
		do_lookup(Comm::refine_to_string(Comm::vector_lookup(res$result, 2)));
		do_lookup(Comm::refine_to_string(Comm::vector_lookup(res$result, 3)));
		}
	timeout query_timeout
		{
		print "clone keys query timeout";
		terminate();
		}
	}

event bro_init()
	{
	Comm::enable();
	Comm::subscribe_to_events("bro/event/ready");
	Comm::listen(broker_port, "127.0.0.1");
	}

@TEST-END-FILE

@TEST-START-FILE master.bro

global query_timeout = 15sec;

const broker_port: port &redef;
redef exit_only_after_terminate = T;

global h: opaque of Store::Handle;

function dv(d: Comm::Data): Comm::DataVector
	{
	local rval: Comm::DataVector;
	rval[0] = d;
	return rval;
	}

global ready: event();

event Comm::outgoing_connection_broken(peer_address: string,
                                       peer_port: port)
	{
	terminate();
	}

event Comm::outgoing_connection_established(peer_address: string,
                                            peer_port: port,
                                            peer_name: string)
	{
	local myset: set[string] = {"a", "b", "c"};
	local myvec: vector of string = {"alpha", "beta", "gamma"};
	h = Store::create_master("mystore");
	Store::insert(h, Comm::data("one"), Comm::data(110));
	Store::insert(h, Comm::data("two"), Comm::data(223));
	Store::insert(h, Comm::data("myset"), Comm::data(myset));
	Store::insert(h, Comm::data("myvec"), Comm::data(myvec));
	Store::increment(h, Comm::data("one"));
	Store::decrement(h, Comm::data("two"));
	Store::add_to_set(h, Comm::data("myset"), Comm::data("d"));
	Store::remove_from_set(h, Comm::data("myset"), Comm::data("b"));
	Store::push_left(h, Comm::data("myvec"), dv(Comm::data("delta")));
	Store::push_right(h, Comm::data("myvec"), dv(Comm::data("omega")));

	when ( local res = Store::size(h) )
		{ event ready(); }
	timeout query_timeout
		{
		print "master size query timeout";
		terminate();
		}
	}

event bro_init()
	{
	Comm::enable();
	Comm::auto_event("bro/event/ready", ready);
	Comm::connect("127.0.0.1", broker_port, 1secs);
	}

@TEST-END-FILE
