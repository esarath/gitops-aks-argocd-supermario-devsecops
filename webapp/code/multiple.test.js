jest.mock('bcrypt', function () {
    return {
        hashSync: jest.fn(function (value, rounds) {
            return 'hashed:' + value + ':' + rounds;
        })
    };
}, { virtual: true });

jest.mock('child_process', function () {
    return {
        execFile: jest.fn(function (cmd, args, callback) {
            callback(null, args.join(' '), '');
        })
    };
});

var multiple = require('./multiple');

describe('executeCommand', function () {
    it('runs echo via execFile with an argument array, not a shell string', function () {
        var execFile = require('child_process').execFile;
        multiple.executeCommand(['hello world'], function (err, stdout) {
            expect(err).toBeNull();
            expect(stdout).toBe('hello world');
        });
        expect(execFile).toHaveBeenCalledWith('echo', ['hello world'], expect.any(Function));
    });

    it('propagates errors to the callback instead of throwing', function () {
        var execFile = require('child_process').execFile;
        execFile.mockImplementationOnce(function (cmd, args, callback) {
            callback(new Error('boom'));
        });
        multiple.executeCommand(['x'], function (err) {
            expect(err).toBeInstanceOf(Error);
        });
    });
});

describe('hashPassword', function () {
    it('hashes via bcrypt instead of storing/using plaintext directly', function () {
        var hashed = multiple.hashPassword('user123');
        expect(hashed).toBe('hashed:user123:12');
        expect(hashed).not.toBe('user123');
    });
});

describe('getUserProfile', function () {
    var db;
    beforeEach(function () {
        db = { query: jest.fn(function () { return 'profile-row'; }) };
    });

    it('throws when the requesting user is not authorized (fixes IDOR)', function () {
        var requestingUser = { canAccess: function () { return false; } };
        expect(function () {
            multiple.getUserProfile(123, requestingUser, db);
        }).toThrow('Not authorized');
        expect(db.query).not.toHaveBeenCalled();
    });

    it('throws when no requesting user is supplied', function () {
        expect(function () {
            multiple.getUserProfile(123, null, db);
        }).toThrow('Not authorized');
    });

    it('queries with a parameterized statement when authorized', function () {
        var requestingUser = { canAccess: function () { return true; } };
        var result = multiple.getUserProfile(123, requestingUser, db);
        expect(result).toBe('profile-row');
        expect(db.query).toHaveBeenCalledWith(
            'SELECT * FROM user_profiles WHERE id = ?',
            [123]
        );
    });
});

describe('findUserByUsername', function () {
    it('uses a parameterized query instead of string concatenation (fixes SQL injection)', function () {
        var db = { query: jest.fn(function () { return 'user-row'; }) };
        var result = multiple.findUserByUsername("'; DROP TABLE users; --", db);
        expect(result).toBe('user-row');
        expect(db.query).toHaveBeenCalledWith(
            'SELECT * FROM users WHERE username = ?',
            ["'; DROP TABLE users; --"]
        );
    });
});

describe('renderGreeting and renderUserInput', function () {
    var originalDocument;

    beforeEach(function () {
        originalDocument = global.document;
        global.document = {
            getElementById: jest.fn()
        };
    });

    afterEach(function () {
        global.document = originalDocument;
    });

    it('sets textContent instead of using document.write (fixes DOM XSS)', function () {
        var el = {};
        global.document.getElementById.mockReturnValue(el);
        multiple.renderGreeting('Mario');
        expect(el.textContent).toBe('Hello, Mario');
    });

    it('does nothing when the greeting element is missing', function () {
        global.document.getElementById.mockReturnValue(null);
        expect(function () { multiple.renderGreeting('Mario'); }).not.toThrow();
    });

    it('renders untrusted input as text, never as HTML', function () {
        var el = {};
        global.document.getElementById.mockReturnValue(el);
        multiple.renderUserInput("<img src=x onerror=alert('XSS')>");
        expect(el.textContent).toBe("<img src=x onerror=alert('XSS')>");
        expect(el.innerHTML).toBeUndefined();
    });
});

describe('fetchData', function () {
    var originalFetch;

    beforeEach(function () {
        originalFetch = global.fetch;
    });

    afterEach(function () {
        global.fetch = originalFetch;
    });

    it('performs an async fetch instead of a synchronous XMLHttpRequest', function () {
        global.fetch = jest.fn(function () {
            return Promise.resolve({ text: function () { return Promise.resolve('data'); } });
        });
        return multiple.fetchData('https://api.example.com/data').then(function (text) {
            expect(text).toBe('data');
            expect(global.fetch).toHaveBeenCalledWith('https://api.example.com/data');
        });
    });

    it('rethrows on failure', function () {
        global.fetch = jest.fn(function () { return Promise.reject(new Error('network down')); });
        return multiple.fetchData('https://api.example.com/data').catch(function (err) {
            expect(err.message).toBe('network down');
        });
    });
});
