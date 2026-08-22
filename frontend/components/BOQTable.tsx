import type { BOQ } from "@/lib/api";

export function BOQTable({ boq }: { boq: BOQ }) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full border-collapse text-sm" aria-label="Bill of Quantities">
        <thead>
          <tr className="border-b border-slate-300 text-left text-xs uppercase text-slate-500">
            <th className="py-2 pr-2">Cost Head</th>
            <th className="py-2 pr-2">Quantity</th>
            <th className="py-2 pr-2">Rate</th>
            <th className="py-2 pr-2 text-right">Amount</th>
          </tr>
        </thead>
        <tbody>
          {boq.lines.map((line) => (
            <tr key={line.cost_head_id} className="border-b border-slate-100">
              <td className="py-2 pr-2">{line.name}</td>
              <td className="py-2 pr-2">
                {line.billing_quantity} {line.billing_unit}
              </td>
              <td className="py-2 pr-2">{line.rate_per_unit ?? "\u2014"}</td>
              <td className="py-2 pr-2 text-right">{line.amount ?? "\u2014"}</td>
            </tr>
          ))}
        </tbody>
        <tfoot>
          <tr className="border-t border-slate-300">
            <td colSpan={3} className="py-2 pr-2 text-right font-medium">
              Subtotal
            </td>
            <td className="py-2 pr-2 text-right font-medium">{boq.subtotal}</td>
          </tr>
          {boq.contractor_profit_percent && (
            <tr>
              <td colSpan={3} className="py-1 pr-2 text-right text-slate-500">
                Contractor profit ({boq.contractor_profit_percent}%)
              </td>
              <td className="py-1 pr-2 text-right text-slate-500">{boq.contractor_profit_amount}</td>
            </tr>
          )}
          <tr>
            <td colSpan={3} className="py-2 pr-2 text-right text-lg font-bold">
              Grand Total
            </td>
            <td className="py-2 pr-2 text-right text-lg font-bold">{boq.grand_total}</td>
          </tr>
        </tfoot>
      </table>
    </div>
  );
}
