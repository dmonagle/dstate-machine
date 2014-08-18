module state_machine;

struct StateMachineEventAttribute {
	string stateName;
}

struct StateMachineFromAttribute {
	string[] states;
}

struct StateMachineToAttribute {
	string[] states;
}

@property StateMachineEventAttribute event(string stateName = "state") {
	return StateMachineEventAttribute(stateName);
}

StateMachineFromAttribute from(string[] states...) {
	return StateMachineFromAttribute(states);
}

StateMachineToAttribute to(string[] states...) {
	return StateMachineToAttribute(states);
}


template Tuple (T...) {
	alias Tuple = T;
}

class InvalidEventException : Exception {
	this(string s) { super(s); }
}

class InvalidTransitionException : Exception {
	this(string s) { super(s); }
}

string defineStateMachine(Class, Enum, string name = "state")() {
	import vibe.internal.meta.uda;
	import std.string;
	
	string capName;
	capName ~= toUpper(name[0..1]);
	capName ~= name[1..$];
	
	string enumCode = "enum " ~ capName ~ "Event { ";
	string transitionCode = Enum.stringof ~ " transition(" ~ capName ~ "Event event) {";
	string transitionStringCode = Enum.stringof ~ " transition(string eventName) {";
	
	transitionCode ~= "final switch(event) {";
	transitionStringCode ~= "switch(eventName) {";
	foreach (memberName; __traits(allMembers, Class)) {
		static if (is(typeof(__traits(getMember, Class.init, memberName)))) {
			alias member = Tuple!(__traits(getMember, Class, memberName));
			alias memberType = typeof(__traits(getMember, Class, memberName));
			alias eventUDA = findFirstUDA!(StateMachineEventAttribute, member);
			static if (eventUDA.found) {
				enumCode ~= memberName ~ ",";
				transitionStringCode ~= "case \"" ~ memberName ~ "\": return transition(" ~ capName ~ "Event." ~ memberName ~ ");";
				transitionCode ~= "case " ~ capName ~ "Event." ~ memberName ~ ": {";
				transitionCode ~= "_" ~ name ~ " = " ~ memberName ~ "();";
				transitionCode ~= "return _" ~ name ~ ";";
				transitionCode ~= "}";
			}
		}
	}
	enumCode ~= "}";
	
	transitionCode ~= "}}"; // End function and switch
	transitionStringCode ~= "default: throw new InvalidEventException(\"No event called '\" ~ eventName ~ \"'\");}}"; // End function and switch
	
	string code;
	code ~= enumCode;
	code ~= transitionCode;
	code ~= transitionStringCode;
	code ~= "@property " ~ Enum.stringof ~ " " ~ name ~ "() { return _" ~ name ~ "; }";
	code ~= "private {";
	code ~= Enum.stringof ~ " _" ~ name ~ ";";
	code ~= "}";
	
	return code;
}

unittest {
	import std.exception;
	
	class Task {
		enum State {
			created,
			todo,
			closed,
		}
		
		mixin (defineStateMachine!(Task, State));
		
		@event @from("created") @to("todo", "closed") State makeTodo() {
			return State.todo;
		}
	}
	
	auto t = new Task();
	assert(t.state == Task.State.created);
	assert(t.transition(Task.StateEvent.makeTodo) == Task.State.todo);
	assert(t.state == Task.State.todo);
	
	assertThrown!InvalidEventException(t.transition("wrongEvent"));
}