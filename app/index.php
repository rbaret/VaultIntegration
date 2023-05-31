<!--This small script will fetch the secrets from Vault and use them to connect to the database and select the users from the users table
The vault token is stored in environment variables -->
<html>
<head>
<title> Demo project </title>
</head>
<body>
<h1> Demo project </h1>
<h2> Refresh the page to see the new credentials and added records </h2>

<?php
// Get the Vault token from the environment variable
$VAULT_TOKEN = getenv("VAULT_TOKEN");
// Fetch the secrets from Vault
$database_credentials = json_decode(shell_exec("curl -s --header \"X-Vault-Token: ${VAULT_TOKEN}\" http://vault:8200/v1/database/creds/appreadonly"), true);

echo "<p>Current DB credentials: <br/> Login : " . $database_credentials['data']['username'] ." <br /> Password : " . $database_credentials['data']['password'] . "</p>";
// Connect to the database
$mysqli = new mysqli("database", $database_credentials['data']['username'], $database_credentials['data']['password'], "app");

// Check connection
if ($mysqli->connect_errno) {
    echo "Failed to connect to MySQL: " . $mysqli->connect_error;
    exit();
}

// Select the users from the users table

$result = $mysqli->query("SELECT * FROM users");

echo "<h2>Users</h2>";

echo "<table border='1'>";
echo "<tr><th>id</th><th>name</th></tr>";

while ($row = $result->fetch_assoc()) {
    echo "<tr><td>" . $row['id'] . "</td><td>" . $row['name'] . "</td></tr>";
}

echo "</table>";

$mysqli->close();

// Open a new connection to the database with the readwrite permissions
$database_credentials = json_decode(shell_exec("curl -s --header \"X-Vault-Token: ${VAULT_TOKEN}\" http://vault:8200/v1/database/creds/appreadwrite"), true);

echo "<p>Current DB credentials: <br/> Login : " . $database_credentials['data']['username'] ." <br /> Password : " . $database_credentials['data']['password'] . "</p>";

// Connect to the database
$mysqli = new mysqli("database", $database_credentials['data']['username'], $database_credentials['data']['password'], "app");
// Check connection
if ($mysqli->connect_errno) {
    echo "Failed to connect to MySQL: " . $mysqli->connect_error;
    exit();
}
// Insert a new user with a random name
$rand = substr(md5(microtime()),rand(0,26),rand(5,9)); 
echo "<p>Inserting a new user with name : " . $rand . "</p>";
// Prepare the query
$stmt = $mysqli->prepare("INSERT INTO users (name) VALUES (?)");
// Bind the parameter
$stmt->bind_param("s", $rand);
// Execute the query
$stmt->execute();
// Close the connection
$stmt->close();
?>
</body>
</html>