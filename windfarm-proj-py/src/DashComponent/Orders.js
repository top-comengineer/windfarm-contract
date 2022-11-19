import * as React from "react";
import Link from "@mui/material/Link";
import Table from "@mui/material/Table";
import TableBody from "@mui/material/TableBody";
import TableCell from "@mui/material/TableCell";
import TableHead from "@mui/material/TableHead";
import TableRow from "@mui/material/TableRow";
import Title from "./Title";

// Generate Order Data
function createData(
  id,
  turbineId,
  PolicyAmount,
  dailyPremium,
  latitude,
  longitude
) {
  return { id, turbineId, PolicyAmount, dailyPremium, latitude, longitude };
}

const rows = [
  createData(0, "31337", 2.9, 0.02211, "49.703168", "-125.630035"),
  createData(1, "42069", 2.7, 0.01971, "49.698892", "-125.615876"),
  createData(2, "90210", 3.5, 0.02555, "49.723435", "-125.599923"),
];

function preventDefault(event) {
  event.preventDefault();
}

export default function Orders() {
  return (
    <React.Fragment>
      <Title>Your Wind Farm Policies (example)</Title>
      <Table size="small">
        <TableHead>
          <TableRow>
            <TableCell>Turbine ID</TableCell>
            <TableCell>Policy Amount</TableCell>
            <TableCell>Daily Premium</TableCell>
            <TableCell>Latitude</TableCell>
            <TableCell>Longitude</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          {rows.map((row) => (
            <TableRow key={row.id}>
              <TableCell>{row.turbineId}</TableCell>
              <TableCell>{`${row.PolicyAmount} ETH`}</TableCell>
              <TableCell>{`${row.dailyPremium} ETH`}</TableCell>
              <TableCell>{row.latitude}</TableCell>
              <TableCell>{row.longitude}</TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </React.Fragment>
  );
}
