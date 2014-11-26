module state_machine;

import std.conv;
import std.string;

version (Have_vibe_d) {
	pragma(msg, "Compiling d-state-machine with vibe.d support");
}

struct SMTransitionEventAttribute {
	string stateEnumName;
}

SMTransitionEventAttribute transitionEvent(string stateName) {
	return SMTransitionEventAttribute(stateName);
}

struct SMBeforeTransitionToAttribute {
	string state;
}

SMBeforeTransitionToAttribute beforeTransitionTo(string state) {
	return SMBeforeTransitionToAttribute(state);
}

struct SMAfterTransitionToAttribute {
	string state;
}

SMAfterTransitionToAttribute afterTransitionTo(string state) {
	return SMAfterTransitionToAttribute(state);
}

struct SMFromStateAttribute {
	string[] states;
}

SMFromStateAttribute fromState(string[] states...) {
	return SMFromStateAttribute(states);
}

template camelize(string name) {
	immutable string camelize = toLower(name[0..1]) ~ name[1..$];
}

unittest {
	assert(camelize!"StatusString" == "statusString");
}

import std.traits;
import std.typetuple : TypeTuple;

template findUDA(UDA, alias Symbol) {
	private struct UdaSearchResult(alias UDA) {
		alias value = UDA;
		bool found = false;
		long index = -1;
	}

	private template extract(size_t index, attributes...) {
		static if (!attributes.length) enum extract = UdaSearchResult!(null)(false, -1);
		else {
			static if (is(typeof(attributes[0]) == UDA))
				enum extract = UdaSearchResult!(attributes[0])(true, index);
			else 
				enum extract = extract!(index + 1, attributes[1..$]);
		}
	}

	private alias TypeTuple!(__traits(getAttributes, Symbol)) udaTuple;
	enum findUDA = extract!(0, udaTuple);
}

/// StateProperty 
struct StateProperty(StateEnum) {
	private {
		StateEnum _state;
	}

	alias state this;

	@property void forceState(StateEnum state) { _state = state; }
	@property StateEnum state() const {
		return _state;
	}

	@safe string toString() const {
		return to!string(_state);
	}

	version (Have_vibe_d) {
		import vibe.data.json;
		import vibe.data.bson;
		import std.conv;

		static StateProperty fromJson(Json value) {
			StateProperty state;
			if (value.type == Json.Type.string) {
				state.forceState(to!StateEnum(value.get!string));
			}
			return state;
		}
		
		Json toJson() const {
			return Json(_state.to!string);
		}

		static StateProperty fromBson(Bson value) {
			StateProperty state;
			if (value.type == Bson.Type.string) {
				state.forceState(to!StateEnum(value.get!string));
			}
			return state;
		}
		
		Bson toBson() const {
			return Bson(_state.to!string);
		}
	}
}

unittest {
	enum Status {
		created,
		todo,
		closed,
		cancelled,
	}
	
	StateProperty!(Status) status;
	
	status.forceState(Status.todo);
	assert(status == Status.todo);
}

version (Have_vibe_d) {
	unittest {
		import vibe.d;
		
		struct Task {
			enum Status {
				created,
				todo,
				closed,
				cancelled,
			}
			
			StateProperty!Status status;
		}
		
		Task task;
		
		auto toJ = serializeToJson(task);
		import std.stdio;

		auto jSource = parseJsonString(`{"status": "todo"}`);
		deserializeJson(task, jSource);
		import std.stdio;
		assert (task.status == Task.Status.todo);
		task.status.forceState(Task.Status.closed);
		assert (task.status == Task.Status.closed);
	}
}

mixin template StateMachine(Parent, StateEnum) {
	import std.algorithm;

	static immutable string statePropertyName = camelize!(StateEnum.stringof);

	// Create the state member 
	static immutable string propertyDef = StateEnum.stringof ~ " " ~ statePropertyName ~ ";";
	version (Have_vibe_d) {
		@byName mixin(propertyDef);
	}
	else {
		mixin(propertyDef);
	}

	/// Convenience property to set the state by the statePropertyName
	mixin(`@property void ` ~ statePropertyName ~ `Transition(` ~  StateEnum.stringof ~ ` s) {
		stateProperty = s;
	}`);

	/// Convenience property to accept a string state via the prefered property name
	mixin(`@property void ` ~ statePropertyName ~ `Transition(string s) {
		stateProperty = s.to!` ~ StateEnum.stringof ~ `;
	}`);

	@property void stateProperty(StateEnum s) {
		static if (is(Parent == class) || is(Parent == struct)) {
			bool checkStates = false;
			bool transitionSuccessful = true;

			foreach (memberName; __traits(allMembers, Parent)) {
				static if (is(typeof(__traits(getMember, Parent.init, memberName)) == function)) {
					string[] fromStates;
					alias member = TypeTuple!(__traits(getMember, Parent, memberName));
					alias transitionUDA = findUDA!(SMTransitionEventAttribute, member);
					static if (transitionUDA.found && (transitionUDA.value.stateEnumName == StateEnum.stringof)) {
						pragma(msg, "StateMachine event '" ~ memberName ~ "' for '" ~ Parent.stringof ~ "'")
						alias beforeTransitionUDA = findUDA!(SMBeforeTransitionToAttribute, member);
						alias afterTransitionUDA = findUDA!(SMAfterTransitionToAttribute, member);
						static assert(beforeTransitionUDA.found ^ afterTransitionUDA.found, "Must have exactly one of beforeTransitionTo or afterTransitionTo UDA on a @transitionEvent");

						alias fromStateUDA = findUDA!(SMFromStateAttribute, member);

						static if (fromStateUDA.found) {
							fromStates = fromStateUDA.value.states;
						}
						else {
							fromStates = [];
						}

						if (fromStates.length == 0 || fromStates.canFind(mixin(statePropertyName).to!string)) {
							static if (beforeTransitionUDA.found) {
								if (s == to!StateEnum(beforeTransitionUDA.value.state)) {
									import std.stdio;
									writeln("Before: " ~ s.to!string);
									if (is(ReturnType!member == bool)) {
										// Execute the transition function and check result
										if(!mixin(memberName)) {
											// Need to throw an exception here
											transitionSuccessful = false;
											assert(false);
										}

									}
									else {
										// Just execute the transition function
										mixin(memberName ~ ";");
									}
								}
							}
							else {
								if (s == to!StateEnum(afterTransitionUDA.value.state)) {
									import std.stdio;
									writeln("After: " ~ s.to!string);
									// Execute the transition function
									mixin(memberName ~ ";");
								}
							}
						}
					}
				}
			}
			// Set the state to the target if the transition was successful
			if (transitionSuccessful) mixin(statePropertyName) = s;
		}
	}

}

unittest {
	struct Task {
		enum Status {
			created,
			todo,
			closed,
			cancelled,
		}

		bool isClosed = false;
		bool isCancelled = false;

		mixin StateMachine!(Task, Status);

		@transitionEvent("Status") @afterTransitionTo("todo") void afterTodo() {
			isClosed = false;
			isCancelled = false;
		}

		@transitionEvent("Status") @afterTransitionTo("closed") @fromState("todo") void closeCleanup() {
			isClosed = true;
		}

		@transitionEvent("Status") @beforeTransitionTo("cancelled") bool cancelledCleanup() {
			if (isClosed) return false;
			isCancelled = true;
			return true;
		}
	}

	Task task;
	task.status = Task.Status.todo;
	assert(task.status == Task.Status.todo);
	task.statusTransition = "closed";
	assert(task.status == Task.Status.closed);
	assert(task.isClosed == true);
	task.statusTransition = "todo";
	task.statusTransition = "cancelled";
	assert(task.isCancelled == true);
}

