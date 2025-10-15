/////////////////////////////////
// *** Helper util functions (internal) ***
////////////////////////////////

function isBin(o) {
    try {
        return !!o.$binary && !!o.$type;
    } catch (e) {
        return false;
    }
}

function str(o) {
    if (o === undefined) {
        return "undefined";
    }
    if (o === null) {
        return "null";
    }
    if (isBin(o)) {
        return "BinData(" + parseInt(o.$type) + ", " + o.$binary.toString().slice(0, 20) + "...)";
    }
    if (typeof o === "string") {
        return "" + o.toString() + "";
    }
    if (isBSON(o)) {
        return JSON.stringify(o);
    }
    let stringified;
    if (Array.isArray(o)) {
        if (o.length === 0) {
            return "[]";
        }
        stringified = o.map(item => String(item).toString()).join(", ");
        if (!Boolean(stringified)) {
            return "[]";
        }
        if (stringified.length < 200) {
            let stringifiedRecursive = o.map(item => str(item)).join(", ");

            if (stringifiedRecursive.length < 200) {
                return "[" + stringifiedRecursive + "]";
            }
            return "[" + stringified + "]";
        }
        return "[" + str(o[0]) + " ... " + str(o[o.length - 1]) + "]";
    }
    return o.toString();
}

function isBSON(o) {
    try {
        return o.toString().endsWith("BSON]");
    } catch (e) {
        return false;
    }
}

function toJSON(o) {
    return JSON.parse(JSON.stringify(o));
}

function safePredicate(predicate) {
    if (typeof predicate === "string") {
        return safePredicate(string => string === predicate);
    }
    if (predicate.wrapper) {
        return predicate;
    }
    const safe = function (v) {
        try {
            return predicate(v);
        } catch (e) {
            return false;
        }
    };
    safe.wrapper = true;
    return safe;
}

//////////////////////////////////////////////////////
// *** Use the functions below ***
//     Example usage at the bottom of the file
//////////////////////////////////////////////////////

// *** Searching

function searchDeepKeys(obj, keyPredicate, quiet, currentKey) {
    let _keys = new Set();
    keyPredicate = safePredicate(keyPredicate);
    if (!currentKey) {
        currentKey = "";
    }

    if (!obj || obj.length === 0) {
        return [ ..._keys ].sort();
    }
    if (typeof obj === "object") {
        if (Array.isArray(obj)) {
            for (let [ i, val ] of Object.entries(obj)) {
                let fullKey = !!currentKey ? currentKey.toString() + "[" + i + "]" : i;
                for (let key of searchDeepKeys(val, keyPredicate, quiet, fullKey)) {
                    _keys.add(key);
                }

            }
            return [ ..._keys ].sort();
        }
        if (isBSON(obj)) {
            obj = toJSON(obj);
        }
        for (let [ key, val ] of Object.entries(obj)) {
            let fullKey = !!currentKey ? currentKey.toString() + "." + key.toString() : key;
            if (keyPredicate(key)) {
                if (!quiet) {
                    print(fullKey + " = " + str(obj[key]));
                }
                _keys.add(fullKey);
            }
            if (typeof val === "object") {
                for (let deepKey of searchDeepKeys(val, keyPredicate, quiet, fullKey)) {
                    _keys.add(deepKey);
                }

            }

        }
        return [ ..._keys ].sort();

    }
    if (keyPredicate(obj)) {
        _keys.add(currentKey);
    }
    return [ ..._keys ].sort();
}

function searchDeepValues(obj, valuePredicate, quiet, currentKey) {
    // let _keys = new Set();
    let _values = new Set();
    valuePredicate = safePredicate(valuePredicate);
    if (!currentKey) {
        currentKey = "";
    }

    if (!obj || obj.length === 0) {
        return [ ..._values ].sort();
    }
    if (typeof obj === "object") {
        if (Array.isArray(obj)) {
            for (let [ i, val_i ] of Object.entries(obj)) {
                let fullKey = !!currentKey ? currentKey.toString() + "[" + i + "]" : i;
                for (let val_j of searchDeepValues(val_i, valuePredicate, quiet, fullKey)) {
                    _values.add(val_j);
                }

            }
            return [ ..._values ].sort();
        }
        if (isBSON(obj)) {
            obj = toJSON(obj);
        }
        for (let [ key, val ] of Object.entries(obj)) {
            let fullKey = !!currentKey ? currentKey.toString() + "." + key.toString() : key;
            if (valuePredicate(val)) {
                if (!quiet) {
                    print(fullKey + " = " + str(obj[key]));
                    // print("Match: \x1b[1m" + fullKey + "\x1b[22m = " + str(obj[key]));
                }
                _values.add(val);
            }
            if (typeof val === "object") {
                for (let deepValue of searchDeepValues(val, valuePredicate, quiet, fullKey)) {
                    _values.add(deepValue);
                }

            }

        }
        return [ ..._values ].sort();

    }
    if (valuePredicate(obj)) {
        _values.add(obj);
    }
    return [ ..._values ].sort();
}

// Searches both keys and values
function searchDeep(obj, predicate, quiet, currentKey) {
    let keys = new Set();
    let values = new Set();
    predicate = safePredicate(predicate);
    if (!currentKey) {
        currentKey = "";
    }

    if (!obj || obj.length === 0) {
        return [ [ ...keys ].sort(), [ ...values ].sort() ];
    }
    if (typeof obj === "object") {
        if (Array.isArray(obj)) {
            for (let [ i, val_i ] of Object.entries(obj)) {
                let fullKey = !!currentKey ? currentKey.toString() + "[" + i + "]" : i;
                for (let [ key_j, val_j ] of searchDeep(val_i, predicate, quiet, fullKey)) {
                    keys.add(key_j);
                    values.add(val_j);
                }

            }
            return [ [ ...keys ].sort(), [ ...values ].sort() ];
        }
        if (isBSON(obj)) {
            obj = toJSON(obj);
        }
        for (let [ key, val ] of Object.entries(obj)) {
            let fullKey = !!currentKey ? currentKey.toString() + "." + key.toString() : key;
            let valMatches = predicate(val);
            let keyMatches = predicate(key);
            if (valMatches || keyMatches) {
                if (!quiet) {
                    print(fullKey + " = " + str(obj[key]));
                    // print("Match: \x1b[1m" + fullKey + "\x1b[22m = " + str(obj[key]));
                }
                if (valMatches) {
                    values.add(val);
                }
                if (keyMatches) {
                    keys.add(key);
                }
            }

            if (typeof val === "object") {
                for (let [ deepKey, deepValue ] of searchDeep(val, predicate, quiet, fullKey)) {
                    keys.add(deepKey);
                    values.add(deepValue);
                }

            }

        }
        return [ [ ...keys ].sort(), [ ...values ].sort() ];

    }
    if (predicate(obj)) {
        values.add(obj);
    }
    return [ [ ...keys ].sort(), [ ...values ].sort() ];
}

// *** Deleting

// deleteDeep ( { "$or": [ { "_id": { "$regex": /.*GILAD/ } }, { "profile_definition_id": "RS_SANITY_PROFILE__GILAD" } ] } )
function deleteDeep(deleteManyQuery){
    let collection;
    let found;
    for (let collectionName of db.getCollectionNames().filter(name => !name.endsWith("log"))) {
        collection = db.getCollection(collectionName);
        if (collection) {
            found = collection.deleteMany(deleteManyQuery);
        }

    }
}

/////////////////////////////////////////////
// *** Script setup ***
// modify only if you know what you're doing
////////////////////////////////////////////

var collectionNames = db.getCollectionNames().filter(name => !name.endsWith("log"));

function init() {
    const _collections = {};

    const _cursors = {};

    const _documents = {};

    // const _keys = {};

    let collection;
    let cursor;
    let collectionDocuments;
    // let collectionKeys;
    for (let collectionName of collectionNames) {
        collection = db.getCollection(collectionName);
        cursor = collection.find();

        collectionDocuments = cursor.toArray();
        // print("Built collection: " + collectionName);
        if (!collectionDocuments) {
            continue;
        }

        // collectionKeys = flattenListsToSet(collectionDocuments.map(Object.keys));

        _collections[collectionName] = collection;
        _cursors[collectionName] = cursor;
        _documents[collectionName] = collectionDocuments;
        // _keys[collectionName] = collectionKeys;
    }
    return [ _collections, _cursors, _documents ];
}

var [ COLLECTIONS, CURSORS, DOCS ] = init();

///////////////////////
// *** Example Usage ***
///////////////////////

// Where did my user end up in the whole database?
//var foundvals = searchDeepValues(DOCS, key => key.includes("GILAD"), false);
var found = searchDeep(DOCS, value => value == "DEVICE_GILAD_8_IOT", false);

// What collections have fields with 'manager' in them?
//searchDeepKeys(COLLECTIONS, keys => keys.toLowerCase().includes("manager"), false);
