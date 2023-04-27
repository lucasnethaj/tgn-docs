module routes.controller;

import vibe.vibe;
import vibe.d;
import vibe.core.core : runApplication;
import vibe.http.server;
import vibe.data.json;

import std.json;
import std.array;
import std.stdio;
import std.conv;
import std.algorithm;
import std.stdio : writefln;
import std.format;
import std.json : JSONException;

import services.routerService;
import services.fsService;
import services.dartService;

import routes.project.model;

import tagion.hibon.HiBONJSON : toPretty;
import tagion.utils.Miscellaneous : toHexString, decode;
import tagion.dart.DARTBasic : DARTIndex, dartIndex;
import tagion.hibon.HiBONRecord;
import std.digest;
import std.typecons;

public Json[] projectList;
public string filePath = "./source/routes/project/data.json";

/// General Template controller for generating POST, READ and DELETE routes.
struct Controller(T) {

    string name;
    DartService dart_service;
    /** 
     * 
     * Params:
     *   name = name of the type. Used for the routing and fail-handling
     *   router = Reference to the router. For inserting the routes for the POST READ DELETE
     *   dart_service = Reference to the dart_service containing the DART.
     */
    this(const(string) access_token, const(string) name, ref URLRouter router, ref DartService dart_service) {
        this.name = name;
        this.dart_service = dart_service;

        router.get(format("/%s/%s/:entityId", access_token, name), &getT);
        router.delete_(format("/%s/%s/:entityId", access_token, name), &deleteT);
        router.post(format("/%s/%s", access_token, name), &postT);
    }
    /** 
     * Get request for reading specific document. 
     * If the request is not valid according to the recordType we return an error.
     * Params:
     *   req = :entityID. Fingerprint of the Archive stored in the DART.
     *   res = returns the Document
     */
    void getT(HTTPServerRequest req, HTTPServerResponse res) {
        string id = req.params.get("entityId");

        const fingerprint = DARTIndex(decode(id));
        const doc = dart_service.read([fingerprint]);
        if (doc.empty) {
            res.statusCode = HTTPStatus.badRequest;
            res.writeBody(format("Archive with fingerprint=%s, not found in database", id));
            return;
        }
        // Check that the document is the Type that was requested.
        if (!isRecord!T(doc.front)) {
            res.statusCode = HTTPStatus.badRequest;

            res.writeBody(format("Read document not of type=%s", name));
        }

        T data = T(doc.front);
        const(Json) entity_json = serializeToJson(data);

        res.writeJsonBody(entity_json);
        res.statusCode = HTTPStatus.ok;

    }
    /** 
     * Post the document for the specific type.
     * Takes a json request and converts it to a struct.
     * If the data cannot be converted it throws a json error.
     * Params:
     *   req = json document
     *   res = httpserverresponse
     */
    void postT(HTTPServerRequest req, HTTPServerResponse res) {
        struct PostResponse {
            string id;
        }

        T data;

        // check that user submits correct body
        try {
            data = deserializeJson!T(req.json);
        }
        catch (JSONException e) {
            res.statusCode = HTTPStatus.badRequest;
            res.writeBody(format("Request body does not match. JSON struct error, %s", e.msg));
            return;
        }

        const prev_bullseye = dart_service.bullseye;
        const fingerprint = dart_service.modify(data.toDoc);
        const new_bullseye = dart_service.bullseye;
        if (new_bullseye == prev_bullseye) {
            res.statusCode = HTTPStatus.badRequest;
            res.writeBody(format("Entity with fingerprint=%s not added to DART", fingerprint.toHexString));
        }

        PostResponse postResponse;
        postResponse.id = fingerprint.toHexString;

        res.statusCode = HTTPStatus.created;
        res.writeJsonBody(postResponse);
    }
    /** 
     * Deletes the fingerprint
     * Params:
     *   req = :entityID. Fingerprint of the Archive stored in the DART.
     *   res = httpresponse.
     */
    void deleteT(HTTPServerRequest req, HTTPServerResponse res) {
        struct DeleteResponse {
            string message;
        }

        string id = req.params.get("entityId");
        const prev_bullseye = dart_service.bullseye;
        const fingerprint = DARTIndex(decode(id));
        dart_service.remove([fingerprint]);
        const new_bullseye = dart_service.bullseye;

        if (prev_bullseye == new_bullseye) {
            res.statusCode = HTTPStatus.badRequest;
            res.writeBody(format("Entity with fingerprint=%s, not found", fingerprint.toHexString));
            return;
        }

        DeleteResponse deleteResponse;
        deleteResponse.message = "Succesfully deleted";

        res.statusCode = HTTPStatus.ok;
        // res.writeBody(format("Entity with fingerprint=%s deleted", fingerprint.toHexString));
        res.writeJsonBody(deleteResponse);
    }
}
