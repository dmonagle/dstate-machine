module state_machine;

import std.conv;
import std.string;

version (Have_vibe_d) {
	public import vibe.core.log;
	public import vibe.data.serialization;
	pragma(msg, "Compiling d-state-machine with vibe.d support");
}

struct SMTransitionEventAttribute {
	string stateEnumName;
}

SMTransitionEventAttribute transitionEvent(string stateName) {
	return SMTransitionEventAttribute(stateName);
}

struct SMGuardAttribute(alias Function) {
	alias pred = Function;
}

auto guard(alias Function)() {
	return SMGuardAttribute!Function();
}

unittest {
	auto g = guard!(n => ((n % 2) == 0));
	assert(g.pred(2));
}

struct SMFromStateAttribute {
	string[] states;

	this(string[] states) {
		this.states = states;
	}
}

auto fromState(string[] states...) {
	return SMFromStateAttribute(states);
}

struct SMToStateAttribute {
	string[] states;

	this(string[] states) {
		this.states = states;
	}
}

auto toState(string[] states...) {
	return SMToStateAttribute(states);
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

// Not proud of this function, there must be a better way to do the guard.
template guardAttrIndex(udaTuple...) {
	private struct UdaSearchResult(alias UDA) {
		alias value = UDA;
		bool found = false;
		long index = -1;
	}
	
	private template extract(size_t index, attributes...) {
		static if (!attributes.length) enum extract = -1;
		else {
			static if (TypeTuple!(attributes[0]).stringof[$ - 7..$] == "(guard)") {
				enum extract = index;
			}
			else 
				enum extract = extract!(index + 1, attributes[1..$]);
		}
	}
	
	enum guardAttrIndex = extract!(0, udaTuple);
}

mixin template StateMachine(Parent, StateEnum, bool transitionWithoutDefinition = false) {
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
			bool transitionDefined = false;

			auto currentState = mixin(statePropertyName);
			if (currentState == s) return; // No-Op for trying to change the state to it's existing state
			
			foreach (memberName; __traits(allMembers, Parent)) {
				static if (is(typeof(__traits(getMember, Parent.init, memberName)) == function)) {

					// TODO: Change these to arrays of the StateEnum rather than use strings
					string[] toStates;
					string[] fromStates;

					alias member = TypeTuple!(__traits(getMember, Parent, memberName));
					alias transitionUDA = findUDA!(SMTransitionEventAttribute, member);
					static if (transitionUDA.found && (transitionUDA.value.stateEnumName == StateEnum.stringof)) {
						pragma(msg, "StateMachine event '" ~ memberName ~ "' for '" ~ Parent.stringof ~ "'")

						alias fromStateUDA = findUDA!(SMFromStateAttribute, member);
						alias toStateUDA = findUDA!(SMToStateAttribute, member);

						static if (fromStateUDA.found) 
							fromStates = fromStateUDA.value.states;
						else 
							fromStates = [];

						static if (toStateUDA.found) 
							toStates = toStateUDA.value.states;
						else 
							toStates = [];

						if ((fromStates.length == 0 || fromStates.canFind(currentState.to!string)) &&
						    (toStates.length == 0 || toStates.canFind(s.to!string))) {
							transitionDefined = true;

							version (Have_vibe_d) {
								logDebugV("%s %s transition from %s to %s: %s", Parent.stringof, StateEnum.stringof, currentState.to!string, s.to!string, memberName);
							}

							bool guardPassed = true;

							alias TypeTuple!(__traits(getAttributes, member)) attributes;
							// See if there is a guard attribute present
							enum guardIndex = guardAttrIndex!(attributes);
							static if (guardIndex != -1) 
								guardPassed = attributes[guardIndex].pred(this);

							// Execute the transition function
							if (guardPassed) {
								mixin(memberName ~ ";");
							}
							else {
								transitionSuccessful = false;
								// Perhaps we can optionally throw an exception here?
							}
						}
					}
				}
			}
			// Set the state to the target if the transition was successful
			if (transitionSuccessful && (transitionWithoutDefinition ^ transitionDefined)) mixin(statePropertyName) = s;
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

		enum InternalState {
			new_,
			started,
			finished,
		}

		int cancelCount;
		bool isClosed = false;
		bool isCancelled = false;

		mixin StateMachine!(Task, Status);
		mixin StateMachine!(Task, InternalState, true); // Allow transitions without an explicit definition

		private {
			@transitionEvent("Status") @toState("todo") void afterTodo() {
				isClosed = false;
				isCancelled = false;
			}

			@transitionEvent("Status") @toState("closed") @fromState("todo") void closeCleanup() {
				isClosed = true;
			}

			@transitionEvent("Status") @toState("cancelled") @guard!((task) => !task.isClosed) bool cancelledCleanup() {
				cancelCount++;
				if (isClosed) return false;
				isCancelled = true;
				return true;
			}
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
	assert(task.cancelCount == 1);
	task.statusTransition = "cancelled";
	assert(task.isCancelled == true);
	assert(task.cancelCount == 1, "Cancelling fired the transition function but it was already cancelled");

	task.statusTransition = "closed"; // Should not be able to transition as it's not defined
	assert(task.status != Task.Status.closed);

	assert(task.internalState == Task.InternalState.new_);
	task.internalStateTransition = "started";
	assert(task.internalState == Task.InternalState.started);
}

