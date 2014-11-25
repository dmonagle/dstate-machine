module state_machine;

version (Have_vibe_d) {
	import vibe.data.serialization;
}

struct StateMachineEventAttribute {
	string stateName;
}

struct StateMachineFromAttribute {
	string[] states;
}

struct StateMachineToAttribute {
	string state;
}

@property StateMachineEventAttribute event(string stateName = "state") {
	return StateMachineEventAttribute(stateName);
}

StateMachineFromAttribute from(string[] states...) {
	return StateMachineFromAttribute(states);
}

StateMachineToAttribute to(string state) {
	return StateMachineToAttribute(state);
}


class InvalidEventException : Exception {
	this(string s) { super(s); }
}

class InvalidTransitionException : Exception {
	this(string s) { super(s); }
}

template PTuple (T...) {
	alias PTuple = T;
}

template camelize(string name) {
	import std.string;

	immutable string camelize = toLower(name[0..1]) ~ name[1..$];
}

unittest {
	assert(camelize!"StatusString" == "statusString");
}

mixin template StateProperty() {
	// Template to definte the attribute getter
	static template defineGetter(StateEnum) {
		const char[] defineGetter = "const " ~ StateEnum.stringof ~ " " ~ attributeName ~ "() { return _" ~ attributeName ~ "; }";
	}

	// End of templates

	// State Getter
	version (Have_vibe_d) {
		@optional @byName @property mixin(defineGetter!StateEnum);
	} else {
		@property mixin(defineGetter!StateEnum);
	}

	// State Setter
	@property mixin("void " ~ attributeName ~ "(" ~ StateEnum.stringof ~ " value) { _" ~ attributeName ~ " = value; }");
}

mixin template StateMachine(StateEnum) {
	static immutable string attributeName = camelize!(StateEnum.stringof);
	pragma(msg, attributeName);
	// Template to definte private property for the state
	static template defineStateMember(StateEnum, string attributeName) {
		const char[] defineStateMember = StateEnum.stringof ~ " _" ~ attributeName ~ ";";
	}

	private {
		// define the private variable to hold the state
		mixin(defineStateMember!(StateEnum, attributeName));
	}

	mixin StateProperty;

	/// CTFE transition
	bool transition(string eventName, this MixinClass)() {
		import vibe.internal.meta.uda;

		foreach (memberName; __traits(allMembers, MixinClass)) {
			if (memberName == eventName) {
				static if (is(typeof(__traits(getMember, MixinClass.init, memberName)))) {
					alias member = PTuple!(__traits(getMember, MixinClass, memberName));
					alias memberType = typeof(__traits(getMember, MixinClass, memberName));
					alias eventUDA = findFirstUDA!(StateMachineEventAttribute, member);
					static if (eventUDA.found) {
						StateEnum returnState = mixin(memberName);

						// TODO: Check to see if the to and from UDAs are there and whether they align

						mixin("_" ~ attributeName ~ "=returnState;");
						return true;
					}
				}
			}
		}
		throw new InvalidEventException("No event " ~ eventName ~ " for " ~ MixinClass.stringof);
	}

	/// Allows transitions by string name
	bool transition(this MixinClass)(string eventName) {
		import vibe.internal.meta.uda;

		switch (eventName) {
	        foreach (memberName; __traits(allMembers, MixinClass)) {
				static if (is(typeof(__traits(getMember, MixinClass.init, memberName)))) {
					alias member = PTuple!(__traits(getMember, MixinClass, memberName));
					alias memberType = typeof(__traits(getMember, MixinClass, memberName));
					alias eventUDA = findFirstUDA!(StateMachineEventAttribute, member);
					static if (eventUDA.found) {
						case memberName: return transition!(memberName); 
					}
				}
			}
			default: {
				throw new InvalidEventException("No event named " ~ eventName ~ " for class " ~ MixinClass.stringof);
			}
		}
	}
}

unittest {
	import std.exception;

	class Task {
		enum State {
			created,
			todo,
			closed,
			cancelled,
		}
		
		mixin StateMachine!(State);
		
		@event @from("created") @to("todo") 
		State makeTodo() {
			return State.todo;
		}

		@event @from("todo") @to("cancelled") 
		State cancel() {
			return State.cancelled;
		}
	}
	
	auto t = new Task();
	assert(t.state == Task.State.created);
	assertThrown!InvalidEventException(!t.transition!"closed");
	assert(t.transition!"makeTodo");
	assert(t.state == Task.State.todo);
	assert(t.transition("cancel"));
	assert(t.state == Task.State.cancelled);
	assertThrown!InvalidEventException(t.transition("wrongEvent"));
}

unittest {
	import std.exception;
	
	class Task {
		enum Status {
			created,
			todo,
			closed,
			cancelled,
		}
		
		mixin StateMachine!(Status);
		
		@event @from("created") @to("todo") 
		Status makeTodo() {
			return Status.todo;
		}
		
		@event @from("todo") @to("cancelled") 
		Status cancel() {
			return Status.cancelled;
		}
	}
	
	auto t = new Task();
	assert(t.status == Task.Status.created);
	assertThrown!InvalidEventException(!t.transition!"closed");
	assert(t.transition!"makeTodo");
	assert(t.status == Task.Status.todo);
	assert(t.transition("cancel"));
	assert(t.status == Task.Status.cancelled);
	assertThrown!InvalidEventException(t.transition("wrongEvent"));
}
