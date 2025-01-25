import ICRC55 "mo:devefi/ICRC55";
import Core "mo:devefi/core";
import VecSnsNeuron "../../src";
import Result "mo:base/Result";
import Debug "mo:base/Debug";

module {

    public type CreateRequest = {
        #devefi_jes1_snsneuron : VecSnsNeuron.Interface.CreateRequest;
    };

    public type Shared = {
        #devefi_jes1_snsneuron : VecSnsNeuron.Interface.Shared;
    };

    public type ModifyRequest = {
        #devefi_jes1_snsneuron : VecSnsNeuron.Interface.ModifyRequest;
    };

    public class VectorModules(
        m : {
            devefi_jes1_snsneuron : VecSnsNeuron.Mod;
        }
    ) {

        public func get(mid : Core.ModuleId, id : Core.NodeId, vec : Core.NodeMem) : Result.Result<Shared, Text> {

            if (mid == VecSnsNeuron.ID) {
                switch (m.devefi_jes1_snsneuron.get(id, vec)) {
                    case (#ok(x)) return #ok(#devefi_jes1_snsneuron(x));
                    case (#err(x)) return #err(x);
                };
            };

            #err("Unknown variant");
        };

        public func getDefaults(mid : Core.ModuleId) : CreateRequest {
            if (mid == VecSnsNeuron.ID) return #devefi_jes1_snsneuron(m.devefi_jes1_snsneuron.defaults());
            Debug.trap("Unknown variant");

        };

        public func sources(mid : Core.ModuleId, id : Core.NodeId) : Core.EndpointsDescription {
            if (mid == VecSnsNeuron.ID) return m.devefi_jes1_snsneuron.sources(id);
            Debug.trap("Unknown variant");

        };

        public func destinations(mid : Core.ModuleId, id : Core.NodeId) : Core.EndpointsDescription {
            if (mid == VecSnsNeuron.ID) return m.devefi_jes1_snsneuron.destinations(id);
            Debug.trap("Unknown variant");
        };

        public func create(id : Core.NodeId, creq : Core.CommonCreateRequest, req : CreateRequest) : Result.Result<Core.ModuleId, Text> {

            switch (req) {
                case (#devefi_jes1_snsneuron(t)) return m.devefi_jes1_snsneuron.create(id, creq, t);
            };
            #err("Unknown variant or mismatch");
        };

        public func modify(mid : Core.ModuleId, id : Core.NodeId, creq : ModifyRequest) : Result.Result<(), Text> {
            switch (creq) {
                case (#devefi_jes1_snsneuron(r)) if (mid == VecSnsNeuron.ID) return m.devefi_jes1_snsneuron.modify(id, r);
            };
            #err("Unknown variant or mismatch");
        };

        public func delete(mid : Core.ModuleId, id : Core.NodeId) : Result.Result<(), Text> {
            if (mid == VecSnsNeuron.ID) return m.devefi_jes1_snsneuron.delete(id);
            Debug.trap("Unknown variant");
        };

        public func nodeMeta(mid : Core.ModuleId) : ICRC55.ModuleMeta {
            if (mid == VecSnsNeuron.ID) return m.devefi_jes1_snsneuron.meta();
            Debug.trap("Unknown variant");
        };

        public func meta() : [ICRC55.ModuleMeta] {
            [
                m.devefi_jes1_snsneuron.meta(),
            ];
        };

    };
};
