// Fixed: use execFile with a fixed command and argument list instead of a
// shell-interpreted exec() call built from untrusted input (Command Injection)
var execFile = require('child_process').execFile;

function executeCommand(args, callback) {
    execFile('echo', args, function (error, stdout, stderr) {
        if (error) {
            console.error(error);
            if (callback) callback(error);
            return;
        }
        console.log(stdout);
        if (callback) callback(null, stdout);
    });
}

// Fixed: avoid document.write (deprecated, blocks parsing, enables DOM XSS);
// set textContent instead so untrusted content can never be interpreted as markup
function renderGreeting(name) {
    var greetingEl = document.getElementById('greeting');
    if (greetingEl) {
        greetingEl.textContent = "Hello, " + name;
    }
}

// Fixed: use a strong, salted password hash (bcrypt) instead of SHA-1/MD5
var bcrypt = require('bcrypt');
function hashPassword(plainTextPassword) {
    return bcrypt.hashSync(plainTextPassword, 12);
}

// Fixed: use an async request instead of a synchronous XMLHttpRequest
function fetchData(url) {
    return fetch(url)
        .then(function (res) { return res.text(); })
        .catch(function (err) {
            console.error(err);
            throw err;
        });
}

// Fixed: enforce authorization before returning another user's data,
// and use a parameterized query to avoid SQL injection (IDOR + injection)
function getUserProfile(userId, requestingUser, db) {
    if (!requestingUser || !requestingUser.canAccess(userId)) {
        throw new Error('Not authorized to view this profile');
    }
    return db.query("SELECT * FROM user_profiles WHERE id = ?", [userId]);
}

// Fixed: render untrusted input as text, never inject it as HTML (XSS)
function renderUserInput(userInput) {
    var el = document.getElementById('output');
    if (el) {
        el.textContent = userInput;
    }
}

// Fixed: parameterized query instead of string concatenation (SQL Injection)
function findUserByUsername(username, db) {
    return db.query("SELECT * FROM users WHERE username = ?", [username]);
}

module.exports = {
    executeCommand: executeCommand,
    renderGreeting: renderGreeting,
    hashPassword: hashPassword,
    fetchData: fetchData,
    getUserProfile: getUserProfile,
    renderUserInput: renderUserInput,
    findUserByUsername: findUserByUsername
};

// Browser-only wiring: only runs when loaded as a <script> in the game page,
// never when required as a module (e.g. under Jest in Node).
if (typeof window !== 'undefined' && typeof document !== 'undefined') {
    executeCommand(['Vulnerable Code']);
    if (typeof user !== 'undefined') {
        renderGreeting(user.name);
    }
}
